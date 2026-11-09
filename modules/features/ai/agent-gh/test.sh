#!/usr/bin/env bash
# agent-gh.sh 的表驱动测试：假 gh 只打印收到的 GH_TOKEN 与参数，不联网。
# 用法: bash modules/features/ai/agent-gh/test.sh
set -euo pipefail
((BASH_VERSINFO[0] >= 4)) || { echo "需要 bash 4 以上（agent-gh.sh 用了 \${var,,}）" >&2; exit 2; }

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir "$work/bin"

# FAKE_VIEW_OWNER：`gh repo view` 返回的 owner；FAKE_VIEW_FAIL=1 时模拟解析失败
cat >"$work/bin/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "$1 $2" == "repo view" ]]; then
  echo view >>"$FAKE_LOG"
  [[ -n ${FAKE_VIEW_FAIL-} ]] && exit 1
  echo "$FAKE_VIEW_OWNER"
  exit 0
fi
echo "TOKEN=${GH_TOKEN-<unset>} ARGS=$*"
EOF
chmod +x "$work/bin/gh"

pass=0
fail=0

# check <名称> <期望输出> <环境变量...> -- <gh 参数...>
check() {
  local name=$1 want=$2 got
  shift 2
  local envs=()
  while [[ $1 != -- ]]; do
    envs+=("$1")
    shift
  done
  shift
  : >"$work/log"
  got=$(env -i PATH="$work/bin:/usr/bin:/bin" FAKE_LOG="$work/log" AGENT_GH_OWNER=shelken \
    "${envs[@]}" "$BASH" -euo pipefail "$here/agent-gh.sh" "$@" 2>&1) || true
  if [[ $got == "$want" ]]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL %s\n  want: %s\n  got:  %s\n' "$name" "$want" "$got"
  fi
}

# 期望输出的两种形态
agent() { echo "TOKEN=agent-secret ARGS=$*"; }
plain() { echo "TOKEN=<unset> ARGS=$*"; }
T=AGENT_GITHUB_TOKEN=agent-secret
V=FAKE_VIEW_OWNER=none

# ── 三类操作 × owner 命中（-R 的各种写法）
check "issue create -R" "$(agent issue create -R shelken/x -t a)" $T $V -- issue create -R shelken/x -t a
check "issue new 别名" "$(agent issue new -R shelken/x)" $T $V -- issue new -R shelken/x
check "issue comment -R" "$(agent issue comment 1 -R shelken/x -b hi)" $T $V -- issue comment 1 -R shelken/x -b hi
check "pr comment --repo" "$(agent pr comment 3 --repo shelken/x -b hi)" $T $V -- pr comment 3 --repo shelken/x -b hi
check "--repo=值" "$(agent pr comment 3 --repo=shelken/x)" $T $V -- pr comment 3 --repo=shelken/x
check "-R紧跟值" "$(agent pr comment 3 -Rshelken/x)" $T $V -- pr comment 3 -Rshelken/x
check "带主机名" "$(agent pr comment 3 -R github.com/shelken/x)" $T $V -- pr comment 3 -R github.com/shelken/x
check "owner 大小写不敏感" "$(agent pr comment 3 -R SHELKEN/x)" $T $V -- pr comment 3 -R SHELKEN/x

# ── owner 不是自己：用户身份（不设 GH_TOKEN）
check "别人的仓库 -R" "$(plain issue create -R other/x)" $T $V -- issue create -R other/x
check "别人的仓库 pr comment" "$(plain pr comment 1 -R other/x)" $T $V -- pr comment 1 -R other/x
check "仓库名含 owner 字样" "$(plain pr comment 1 -R other/shelken)" $T $V -- pr comment 1 -R other/shelken

# ── owner 的其他来源
check "GH_REPO 命中" "$(agent pr comment 3)" $T $V GH_REPO=shelken/x -- pr comment 3
check "GH_REPO 不命中" "$(plain pr comment 3)" $T $V GH_REPO=other/x -- pr comment 3
check "-R 优先于 GH_REPO" "$(plain pr comment 3 -R other/x)" $T $V GH_REPO=shelken/x -- pr comment 3 -R other/x
check "链接命中" "$(agent issue comment https://github.com/shelken/x/issues/1 -b hi)" $T $V -- issue comment https://github.com/shelken/x/issues/1 -b hi
check "PR 链接不命中" "$(plain pr comment https://github.com/other/x/pull/2 -b hi)" $T $V -- pr comment https://github.com/other/x/pull/2 -b hi
check "链接优先于 -R" "$(agent pr comment https://github.com/shelken/x/pull/2 -R other/x)" $T $V -- pr comment https://github.com/shelken/x/pull/2 -R other/x
check "当前目录命中" "$(agent issue create -t a)" $T FAKE_VIEW_OWNER=shelken -- issue create -t a
check "当前目录不命中" "$(plain issue create -t a)" $T FAKE_VIEW_OWNER=other -- issue create -t a
check "当前目录解析失败时原样交给 gh" "$(plain issue create -t a)" $T FAKE_VIEW_FAIL=1 -- issue create -t a

# ── 不在三类内：即使 owner 是自己也不换，且不额外调用 gh
check "pr create 不换" "$(plain pr create -R shelken/x)" $T $V -- pr create -R shelken/x
check "issue close 不换" "$(plain issue close 1 -R shelken/x -c hi)" $T $V -- issue close 1 -R shelken/x -c hi
check "pr review 不换" "$(plain pr review 1 -R shelken/x -c)" $T $V -- pr review 1 -R shelken/x -c
check "api 不换" "$(plain api repos/shelken/x/issues)" $T $V -- api repos/shelken/x/issues
check "无参数" "$(plain)" $T $V --
check "只有一个参数" "$(plain issue)" $T $V -- issue

: >"$work/log"
env -i PATH="$work/bin:/usr/bin:/bin" FAKE_LOG="$work/log" AGENT_GH_OWNER=shelken $T \
  "$BASH" -euo pipefail "$here/agent-gh.sh" pr list >/dev/null
if [[ -s $work/log ]]; then
  fail=$((fail + 1))
  echo "FAIL 未命中的命令不应调用 gh repo view"
else
  pass=$((pass + 1))
fi

# ── token 缺失或为空
missing=$(printf 'agent-gh: 缺少 AGENT_GITHUB_TOKEN。\n对 shelken 的仓库执行以下操作必须使用 agent 专属 token:\n  gh issue create\n  gh issue new\n  gh issue comment\n  gh pr comment\n本次调用未执行。')
check "token 缺失时失败" "$missing" $V -- issue create -R shelken/x
check "token 为空时失败" "$missing" AGENT_GITHUB_TOKEN= $V -- pr comment 1 -R shelken/x
check "token 缺失但仓库不是自己：原样放行" "$(plain issue create -R other/x)" $V -- issue create -R other/x
check "token 缺失但命令不在三类内：原样放行" "$(plain pr create -R shelken/x)" $V -- pr create -R shelken/x

# 失败时不得调用真实 gh（既不创建也不评论）
if [[ $(env -i PATH="$work/bin:/usr/bin:/bin" FAKE_LOG="$work/log" AGENT_GH_OWNER=shelken $V \
  "$BASH" -euo pipefail "$here/agent-gh.sh" issue create -R shelken/x 2>/dev/null) == *TOKEN=* ]]; then
  fail=$((fail + 1))
  echo "FAIL token 缺失时不得调用 gh"
else
  pass=$((pass + 1))
fi

printf '%d 通过，%d 失败\n' "$pass" "$fail"
((fail == 0))
