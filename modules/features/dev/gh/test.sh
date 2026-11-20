#!/usr/bin/env bash
set -euo pipefail
((BASH_VERSINFO[0] >= 4)) || { echo "需要 bash 4 以上（agent-gh.sh 用了 \${var,,}）" >&2; exit 2; }

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir "$work/bin"

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

agent() { echo "TOKEN=agent-secret ARGS=$*"; }
plain() { echo "TOKEN=<unset> ARGS=$*"; }
T=AGENT_GITHUB_TOKEN=agent-secret
V=FAKE_VIEW_OWNER=none

check "issue create -R" "$(agent issue create -R shelken/x -t a)" $T $V -- issue create -R shelken/x -t a
check "issue new 别名" "$(agent issue new -R shelken/x)" $T $V -- issue new -R shelken/x
check "issue comment -R" "$(agent issue comment 1 -R shelken/x -b hi)" $T $V -- issue comment 1 -R shelken/x -b hi
check "pr comment --repo" "$(agent pr comment 3 --repo shelken/x -b hi)" $T $V -- pr comment 3 --repo shelken/x -b hi
check "--repo=值" "$(agent pr comment 3 --repo=shelken/x)" $T $V -- pr comment 3 --repo=shelken/x
check "-R紧跟值" "$(agent pr comment 3 -Rshelken/x)" $T $V -- pr comment 3 -Rshelken/x
check "带主机名" "$(agent pr comment 3 -R github.com/shelken/x)" $T $V -- pr comment 3 -R github.com/shelken/x
check "owner 大小写不敏感" "$(agent pr comment 3 -R SHELKEN/x)" $T $V -- pr comment 3 -R SHELKEN/x

check "别人的仓库 -R" "$(plain issue create -R other/x)" $T $V -- issue create -R other/x
check "别人的仓库 pr comment" "$(plain pr comment 1 -R other/x)" $T $V -- pr comment 1 -R other/x
check "仓库名含 owner 字样" "$(plain pr comment 1 -R other/shelken)" $T $V -- pr comment 1 -R other/shelken

check "GH_REPO 命中" "$(agent pr comment 3)" $T $V GH_REPO=shelken/x -- pr comment 3
check "GH_REPO 不命中" "$(plain pr comment 3)" $T $V GH_REPO=other/x -- pr comment 3
check "-R 优先于 GH_REPO" "$(plain pr comment 3 -R other/x)" $T $V GH_REPO=shelken/x -- pr comment 3 -R other/x
check "链接命中" "$(agent issue comment https://github.com/shelken/x/issues/1 -b hi)" $T $V -- issue comment https://github.com/shelken/x/issues/1 -b hi
check "PR 链接不命中" "$(plain pr comment https://github.com/other/x/pull/2 -b hi)" $T $V -- pr comment https://github.com/other/x/pull/2 -b hi
check "链接优先于 -R" "$(agent pr comment https://github.com/shelken/x/pull/2 -R other/x)" $T $V -- pr comment https://github.com/shelken/x/pull/2 -R other/x
check "当前目录命中" "$(agent issue create -t a)" $T FAKE_VIEW_OWNER=shelken -- issue create -t a
check "当前目录不命中" "$(plain issue create -t a)" $T FAKE_VIEW_OWNER=other -- issue create -t a
check "当前目录解析失败时原样交给 gh" "$(plain issue create -t a)" $T FAKE_VIEW_FAIL=1 -- issue create -t a
check "有 token 但 owner 为空：原样放行" "$(plain issue create -t a)" $T FAKE_VIEW_OWNER= -- issue create -t a

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

check "token 缺失时放行" "$(plain issue create -R shelken/x)" $V -- issue create -R shelken/x
check "token 为空时放行" "$(plain pr comment 1 -R shelken/x)" AGENT_GITHUB_TOKEN= $V -- pr comment 1 -R shelken/x
check "token 缺失但仓库不是自己：原样放行" "$(plain issue create -R other/x)" $V -- issue create -R other/x
check "token 缺失但命令不在三类内：原样放行" "$(plain pr create -R shelken/x)" $V -- pr create -R shelken/x

: >"$work/log"
env -i PATH="$work/bin:/usr/bin:/bin" FAKE_LOG="$work/log" AGENT_GH_OWNER=shelken FAKE_VIEW_OWNER=shelken \
  "$BASH" -euo pipefail "$here/agent-gh.sh" issue create -t a >/dev/null
if [[ -s $work/log ]]; then
  fail=$((fail + 1))
  echo "FAIL 没有 token 时不应调用 gh repo view"
else
  pass=$((pass + 1))
fi

printf '%d 通过，%d 失败\n' "$pass" "$fail"
((fail == 0))
