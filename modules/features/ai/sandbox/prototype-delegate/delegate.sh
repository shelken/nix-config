#!/usr/bin/env bash
# 原型（不进 main）：本机一条命令把任务交给执行节点，节点在沙箱里跑 agent 并开 PR。
#   本机子命令：run / tasks / log
#   节点子命令（由本机经 ssh 调用）：_dispatch / _worker / _tasks / _log
# shellcheck disable=SC2016  # jq 过滤器与 bash -c 脚本里的 $ 不应被展开
set -euo pipefail

ROOT_REL='Code/.delegate'
DEFAULT_NODE=yuuko
ID_RE='^[0-9]{8}-[0-9]{6}-[0-9a-f]{4}$'

die() {
  echo "[-] 错误: $*" >&2
  exit 1
}

usage() {
  cat >&2 <<'EOF'
用法:
  delegate.sh run [--node N] [--repo URL] [--base 分支] [--branch 分支名] [--agent pi|omp] ("任务描述" | -f 文件|-)
  delegate.sh tasks [--node N] [--json]
  delegate.sh log <id> [--node N] [--json]
EOF
  exit 2
}

# ---------------------------------------------------------------- 本机

# 把 git 远程地址规范成 https://github.com/<owner>/<repo>.git，并输出 owner/repo
normalize_repo() {
  local u=${1%/} p
  case $u in
    git@github.com:*) p=${u#git@github.com:} ;;
    ssh://git@github.com/*) p=${u#ssh://git@github.com/} ;;
    https://github.com/*) p=${u#https://github.com/} ;;
    *) return 1 ;;
  esac
  p=${p%.git}
  [[ $p =~ ^[^/]+/[^/]+$ ]] || return 1
  echo "$p"
}

ssh_node() {
  local node=$1
  shift
  ssh -o BatchMode=yes "$node" "$@"
}

# 在节点上执行本脚本的子命令（脚本由 run 事先复制过去）
remote() {
  local node=$1
  shift
  ssh_node "$node" "bash ~/$ROOT_REL/bin/delegate.sh $(printf '%q ' "$@")"
}

# 脚本每次由本机复制到节点，节点上不安装
push_script() {
  ssh_node "$1" "mkdir -p ~/$ROOT_REL/bin && cat > ~/$ROOT_REL/bin/delegate.sh" <"$0" || die "复制脚本到 $1 失败"
}

cmd_run() {
  local node=$DEFAULT_NODE repo="" base="" branch="" agent=pi file="" text="" have_text=0
  while (($#)); do
    case $1 in
      --node) node=${2:?--node 需要参数}; shift 2 ;;
      --repo) repo=${2:?--repo 需要参数}; shift 2 ;;
      --base) base=${2:?--base 需要参数}; shift 2 ;;
      --branch) branch=${2:?--branch 需要参数}; shift 2 ;;
      --agent) agent=${2:?--agent 需要参数}; shift 2 ;;
      -f) file=${2:?-f 需要参数}; shift 2 ;;
      -h | --help) usage ;;
      -*) die "未知选项: $1" ;;
      *)
        ((have_text)) && die "只能给一个任务描述"
        text=$1
        have_text=1
        shift
        ;;
    esac
  done

  [[ $agent == pi || $agent == omp ]] || die "--agent 只支持 pi 或 omp"
  if [[ -n $file && $have_text -eq 1 ]]; then die "任务描述与 -f 只能二选一"; fi
  if [[ -z $file && $have_text -eq 0 ]]; then die "缺少任务描述（文字参数或 -f 文件）"; fi
  if [[ -n $file ]]; then
    if [[ $file == - ]]; then
      text=$(cat)
    else
      [[ -f $file ]] || die "任务文件不存在: $file"
      text=$(cat "$file")
    fi
  fi
  [[ -n ${text//[[:space:]]/} ]] || die "任务描述为空"

  local repo_derived=0
  if [[ -z $repo ]]; then
    repo_derived=1
    repo=$(git remote get-url origin 2>/dev/null) || die "当前目录不是带 origin 的 git 仓库，请用 --repo 指定"
  fi
  if [[ -z $base ]]; then
    base=$(git symbolic-ref --short -q HEAD 2>/dev/null) || die "无法推导当前分支，请用 --base 指定"
  fi

  if ((repo_derived)); then
    local cur ahead
    cur=$(git symbolic-ref --short -q HEAD 2>/dev/null) || die "当前处于游离 HEAD，请用 --repo/--base 显式指定"
    git rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1 || die "分支 $cur 没有上游，节点拿不到它。请先执行: git push -u origin $cur"
    ahead=$(git rev-list --count '@{u}..HEAD')
    ((ahead == 0)) || die "分支 $cur 有 $ahead 个未推送提交，节点拿不到它们。请先执行: git push"
  fi

  local owner_repo
  owner_repo=$(normalize_repo "$repo") || die "只支持 github.com 仓库，无法识别: $repo"
  repo="https://github.com/$owner_repo.git"

  local id
  id="$(date +%Y%m%d-%H%M%S)-$(printf '%04x' $((RANDOM % 65536)))"
  [[ -n $branch ]] || branch="delegate/$id"

  push_script "$node"
  printf '%s\n' "$text" | remote "$node" _dispatch "$id" "$node" "$repo" "$owner_repo" "$base" "$branch" "$agent" ||
    die "派发到 $node 失败"

  echo "[+] 已派发到 $node：$owner_repo  $base -> $branch；查看: delegate.sh log $id --node $node" >&2
  echo "$id"
}

cmd_tasks() {
  local node=$DEFAULT_NODE json=0
  while (($#)); do
    case $1 in
      --node) node=${2:?--node 需要参数}; shift 2 ;;
      --json) json=1; shift ;;
      *) die "未知参数: $1" ;;
    esac
  done
  push_script "$node"
  local out
  out=$(remote "$node" _tasks) || die "读取 $node 的任务失败"
  if ((json)); then
    printf '%s\n' "$out"
  else
    {
      printf 'ID\tSTATUS\tREASON\tBRANCH\tPR\n'
      printf '%s\n' "$out" | jq -r '.[] | [.id, .status, (.reason // "-"), .branch, (.pr_url // "-")] | @tsv'
    } | column -t -s $'\t'
  fi
}

cmd_log() {
  local node=$DEFAULT_NODE json=0 id=""
  while (($#)); do
    case $1 in
      --node) node=${2:?--node 需要参数}; shift 2 ;;
      --json) json=1; shift ;;
      -*) die "未知选项: $1" ;;
      *) id=$1; shift ;;
    esac
  done
  [[ -n $id ]] || die "缺少任务 id"
  push_script "$node"
  local out
  out=$(remote "$node" _log "$id") || exit 1
  if ((json)); then
    printf '%s\n' "$out"
  else
    printf '%s\n' "$out" | jq -r '.meta | to_entries[] | "\(.key): \(.value)"'
    echo "== output =="
    printf '%s\n' "$out" | jq -r '.output'
    echo "== log =="
    printf '%s\n' "$out" | jq -r '.log'
  fi
}

# ---------------------------------------------------------------- 节点

# 节点上默认的 ssh/后台环境找不到 nix 与 mise 提供的工具。full 时再补 mise（sb 需要 msb、sec-run）
node_env() {
  cd ~
  export PATH="$HOME/.nix-profile/bin:/etc/profiles/per-user/$USER/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:$PATH"
  export LC_ALL=en_US.UTF-8
  if [[ ${1:-} == full ]]; then
    eval "$(mise env -s bash)"
  fi
  ROOT=$HOME/$ROOT_REL
}

now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
wlog() { echo "[$(date +%H:%M:%S)] $*"; }

meta_set() {
  local f=$TASKDIR/meta.json
  jq "$@" "$f" >"$f.tmp" && mv "$f.tmp" "$f"
}

check_id() {
  [[ $1 =~ $ID_RE ]] || { echo "[-] 错误: 非法任务 id: $1" >&2; exit 1; }
}

node_dispatch() {
  node_env
  local id=$1 node=$2 repo=$3 owner_repo=$4 base=$5 branch=$6 agent=$7
  check_id "$id"
  TASKDIR=$ROOT/tasks/$id
  mkdir -p "$TASKDIR"
  {
    cat
    printf '\n---\n交付约定（由委派脚本附加）：\n'
    printf -- '- 在当前 git 分支上完成改动，并用 git commit 提交（可以多个提交）。\n'
    printf -- '- 不要 push，不要创建 PR，不要切换或新建分支。\n'
    printf -- '- 最后一条回复用中文简要说明：做了什么、怎么验证的。它会原样成为 PR 正文。\n'
  } >"$TASKDIR/prompt.md"
  jq -n --arg id "$id" --arg node "$node" --arg repo "$repo" --arg owner_repo "$owner_repo" \
    --arg base "$base" --arg branch "$branch" --arg agent "$agent" --arg created "$(now)" \
    '{id:$id, node:$node, repo:$repo, owner_repo:$owner_repo, base:$base, branch:$branch, agent:$agent,
      status:"queued", reason:null, agent_rc:null, pr_url:null, created_at:$created,
      started_at:null, finished_at:null, timings:{fetch_s:null, agent_s:null, deliver_s:null}}' \
    >"$TASKDIR/meta.json"
  # 三个标准流都重定向，ssh 才能立即断开；caffeinate 防止任务中途空闲睡眠
  nohup caffeinate -i bash "$ROOT/bin/delegate.sh" _worker "$id" </dev/null >>"$TASKDIR/log" 2>&1 &
  disown
}

FINISHED=0
FETCH_S=null AGENT_S=null DELIVER_S=null

# status reason pr_url
worker_finish() {
  FINISHED=1
  meta_set --arg s "$1" --arg r "${2:-}" --arg pr "${3:-}" --arg t "$(now)" \
    --argjson f "$FETCH_S" --argjson a "$AGENT_S" --argjson d "$DELIVER_S" \
    '.status=$s | .reason=(if $r=="" then null else $r end) | .pr_url=(if $pr=="" then null else $pr end)
     | .finished_at=$t | .timings={fetch_s:$f, agent_s:$a, deliver_s:$d}'
  wlog "结束: $1 ${2:-}"
}

worker_trap() {
  if ((FINISHED == 0)); then worker_finish failed worker_crashed || true; fi
}

# 仓库缓存：同一仓库的 clone/fetch/worktree add 串行（在 lockf 下运行）。
# bare clone 的默认 refspec 会把远端分支写进 refs/heads/*，--prune 会删掉还没推送的任务分支，
# 所以必须改成写进 refs/remotes/origin/*。退出码 11 = 基线分支不存在。
PREPARE_SCRIPT='
set -e
bare=$1 repo=$2 base=$3 branch=$4 work=$5
if [ ! -d "$bare" ]; then
  git clone --bare "$repo" "$bare"
  git -C "$bare" config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"
fi
git -C "$bare" fetch --prune origin
git -C "$bare" rev-parse --verify -q "refs/remotes/origin/$base" >/dev/null || exit 11
git -C "$bare" worktree add --no-track -b "$branch" "$work" "origin/$base"
'

node_worker() {
  local id=$1
  node_env full
  check_id "$id"
  TASKDIR=$ROOT/tasks/$id
  trap worker_trap EXIT

  local tool missing=""
  for tool in sb msb sec-run gh git jq; do
    command -v "$tool" >/dev/null 2>&1 || missing="$missing $tool"
  done
  if [[ -n $missing ]]; then
    wlog "缺少工具:$missing"
    worker_finish failed env_missing
    return 0
  fi

  local repo owner_repo base branch agent
  repo=$(jq -r .repo "$TASKDIR/meta.json")
  owner_repo=$(jq -r .owner_repo "$TASKDIR/meta.json")
  base=$(jq -r .base "$TASKDIR/meta.json")
  branch=$(jq -r .branch "$TASKDIR/meta.json")
  agent=$(jq -r .agent "$TASKDIR/meta.json")
  meta_set --arg t "$(now)" '.status="running" | .started_at=$t'
  wlog "开始: $owner_repo base=$base branch=$branch agent=$agent"

  local bare=$ROOT/repos/github.com/$owner_repo.git lock=$ROOT/repos/github.com/$owner_repo.lock
  local work=$TASKDIR/work t0 rc
  mkdir -p "$(dirname "$bare")"

  t0=$(date +%s)
  rc=0
  lockf -k "$lock" bash -c "$PREPARE_SCRIPT" _ "$bare" "$repo" "$base" "$branch" "$work" || rc=$?
  FETCH_S=$(($(date +%s) - t0))
  if ((rc == 11)); then
    worker_finish failed base_missing
    return 0
  elif ((rc != 0)); then
    worker_finish failed fetch_failed
    return 0
  fi

  t0=$(date +%s)
  rc=0
  (cd "$work" && sb run "$agent" -p "$(cat "$TASKDIR/prompt.md")" >"$TASKDIR/output.md" 2>>"$TASKDIR/log") || rc=$?
  AGENT_S=$(($(date +%s) - t0))
  meta_set --argjson rc "$rc" '.agent_rc=$rc'
  wlog "agent 退出码 $rc，用时 ${AGENT_S}s"

  t0=$(date +%s)
  local n head
  n=$(git -C "$work" rev-list --count "origin/$base..HEAD")
  head=$(git -C "$work" symbolic-ref --short -q HEAD || echo DETACHED)
  [[ $head == "$branch" ]] || wlog "警告: agent 把分支切到了 $head"
  if git -C "$work" ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then
    wlog "警告: 推送前远端已存在分支 $branch（agent 可能自行 push）"
  fi
  if ((n == 0)); then
    DELIVER_S=$(($(date +%s) - t0))
    if ((rc != 0)); then worker_finish failed agent_failed; else worker_finish failed no_commits; fi
    return 0
  fi

  wlog "新提交 $n 个，推送 $branch"
  if ! git -C "$work" push origin "$branch" >>"$TASKDIR/log" 2>&1; then
    DELIVER_S=$(($(date +%s) - t0))
    worker_finish failed push_failed
    return 0
  fi

  local title url body=$TASKDIR/pr-body.md
  title=$(grep -m1 -v '^[[:space:]]*$' "$TASKDIR/prompt.md" | cut -c1-70)
  {
    cat "$TASKDIR/output.md"
    printf '\n---\n由委派任务 %s 生成（agent: %s，节点: %s）\n' "$id" "$agent" "$(jq -r .node "$TASKDIR/meta.json")"
  } >"$body"
  if ! url=$(gh pr create -R "$owner_repo" --base "$base" --head "$branch" --title "$title" --body-file "$body" 2>>"$TASKDIR/log"); then
    DELIVER_S=$(($(date +%s) - t0))
    worker_finish failed pr_failed
    return 0
  fi
  url=$(printf '%s\n' "$url" | tail -n1)
  git -C "$bare" worktree remove --force "$work" >>"$TASKDIR/log" 2>&1 || wlog "警告: 删除 worktree 失败"
  DELIVER_S=$(($(date +%s) - t0))
  worker_finish pr_opened "" "$url"
}

node_tasks() {
  node_env
  shopt -s nullglob
  local files=("$ROOT"/tasks/*/meta.json)
  if ((${#files[@]} == 0)); then
    echo '[]'
    return 0
  fi
  jq -s 'sort_by(.created_at) | reverse' "${files[@]}"
}

node_log() {
  node_env
  local id=${1:?缺少 id}
  check_id "$id"
  TASKDIR=$ROOT/tasks/$id
  [[ -f $TASKDIR/meta.json ]] || { echo "[-] 错误: 任务不存在: $id" >&2; exit 1; }
  local out=$TASKDIR/output.md log=$TASKDIR/log
  [[ -f $out ]] || out=/dev/null
  [[ -f $log ]] || log=/dev/null
  jq -n --slurpfile meta "$TASKDIR/meta.json" --rawfile output "$out" --rawfile log "$log" \
    '{meta:$meta[0], output:$output, log:$log}'
}

# ---------------------------------------------------------------- 入口

sub=${1:-}
[[ -n $sub ]] || usage
shift
case $sub in
  run) cmd_run "$@" ;;
  tasks) cmd_tasks "$@" ;;
  log) cmd_log "$@" ;;
  _dispatch) node_dispatch "$@" ;;
  _worker) node_worker "$@" ;;
  _tasks) node_tasks ;;
  _log) node_log "$@" ;;
  *) usage ;;
esac
