#!/usr/bin/env bash
# sec-run.zsh 的表驱动测试：假 op 按环境文件解析引用，不联网、不碰真实凭据。
# 用法: bash modules/features/secrets/test.sh
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir "$work/bin" "$work/home"

# 假 op：只实现 `op run --no-masking --env-file=… -- <命令>`。
# 引用 op://V/I/F 解析成 "V/I 的值"；报错文本照抄真实 op 的两种格式。
#   FAKE_MISSING_ITEMS  空格分隔的条目名，命中即按「条目不存在」失败
#   FAKE_MISSING_VAULTS 空格分隔的 vault 名，命中即按「vault 不可见」失败
#   FAKE_OP_FAIL        非空时按无法识别的错误失败
#   FAKE_DROP_KEYS      空格分隔的变量名，解析成功但不导出（模拟 op 没给出这个变量）
cat >"$work/bin/op" <<'EOF'
#!/usr/bin/env bash
echo "call token=${OP_SERVICE_ACCOUNT_TOKEN-<unset>}" >>"$FAKE_LOG"
[[ -n ${FAKE_OP_FAIL-} ]] && { echo "[ERROR] 2026/01/01 00:00:00 network is unreachable" >&2; exit 1; }
files=()
while [[ $1 != -- ]]; do
  [[ $1 == --env-file=* ]] && files+=("${1#--env-file=}")
  shift
done
shift
for f in "${files[@]}"; do
  while IFS= read -r line || [[ -n $line ]]; do
    [[ $line =~ ^[[:space:]]*(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]] || continue
    key=${BASH_REMATCH[2]} val=${BASH_REMATCH[3]}
    val=${val#\"} val=${val%\"}
    if [[ $val == op://* ]]; then
      IFS=/ read -r _ _ vault item _ <<<"$val"
      for v in ${FAKE_MISSING_VAULTS-}; do
        [[ $v == "$vault" ]] && { echo "[ERROR] 2026/01/01 00:00:00 \"$vault\" isn't a vault in this account. Specify the vault with its ID or name." >&2; exit 1; }
      done
      for i in ${FAKE_MISSING_ITEMS-}; do
        [[ $i == "$item" ]] && { echo "[ERROR] 2026/01/01 00:00:00 could not resolve item UUID for item $item: could not find item $item in vault abc123" >&2; exit 1; }
      done
      val=${FAKE_VALUE_PREFIX-}"$vault/$item 的值"
    fi
    case " ${FAKE_DROP_KEYS-} " in *" $key "*) continue ;; esac
    export "$key=$val"
  done <"$f"
done
exec "$@"
EOF
chmod +x "$work/bin/op"

base="$work/base.env"
overlay="$work/home/.specific.zsh"
token="$work/token"
echo "tok-secret" >"$token"

pass=0
fail=0

# check <名称> <期望输出> <环境变量...> -- <sec-run 参数...>
# 输出 = sec-run 的 stdout+stderr，末尾追加一行 "rc=<退出码>"
check() {
  local name=$1 want=$2 got rc=0
  shift 2
  local envs=()
  while [[ $1 != -- ]]; do
    envs+=("$1")
    shift
  done
  shift
  : >"$work/log"
  got=$(env -i PATH="$work/bin:/usr/bin:/bin" HOME="$work/home" FAKE_LOG="$work/log" \
    SEC_RUN_BASE="$base" SEC_RUN_TOKEN_FILE="$token" \
    "${envs[@]}" zsh -f "$here/sec-run.zsh" "$@" 2>&1) || rc=$?
  got+=$'\n'"rc=$rc"
  if [[ $got == "$want" ]]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL %s\n  want: %s\n  got:  %s\n' "$name" "${want//$'\n'/$'\n'        }" "${got//$'\n'/$'\n'        }"
  fi
}

# 探针：打印指定变量，未设置的显示 <unset>
probe='for k in "$@"; do eval "v=\${$k-<unset>}"; echo "$k=$v"; done'
P=(sh -c "$probe" _)

printf 'A=op://Agent/ItemA/credential\nB=op://Agent/ItemB/credential\n' >"$base"
rm -f "$overlay"

check "全部解析" $'A=Agent/ItemA 的值\nB=Agent/ItemB 的值\nrc=0' -- "${P[@]}" A B
check "参数与退出码原样传递" $'x y  z\nrc=7' -- sh -c 'echo "$1 $2"; exit 7' _ x "y  z"
check "token 不进入目标命令" $'OP_SERVICE_ACCOUNT_TOKEN=<unset>\nrc=0' -- "${P[@]}" OP_SERVICE_ACCOUNT_TOKEN
check "token 交给 op" $'call token=tok-secret\nrc=0' -- cat "$work/log"
check "没有 token 文件时不设置 token" $'call token=<unset>\nrc=0' SEC_RUN_TOKEN_FILE="$work/none" -- cat "$work/log"
check "值含空格等号换行" $'A=x = y\nz:Agent/ItemA 的值\nrc=0' FAKE_VALUE_PREFIX=$'x = y\nz:' -- "${P[@]}" A

check "op 没给出最后一个变量也算成功" $'A=Agent/ItemA 的值\nB=<unset>\nrc=0' FAKE_DROP_KEYS=B -- "${P[@]}" A B
check "条目不存在：跳过并警告" \
  $'⚠️ [sec-run] 跳过无法解析的引用 op://Agent/ItemB/（变量: B）\nA=Agent/ItemA 的值\nB=<unset>\nrc=0' \
  FAKE_MISSING_ITEMS=ItemB -- "${P[@]}" A B
check "两个条目都不存在" \
  $'⚠️ [sec-run] 跳过无法解析的引用 op://Agent/ItemA/（变量: A）\n⚠️ [sec-run] 跳过无法解析的引用 op://Agent/ItemB/（变量: B）\nA=<unset>\nB=<unset>\nrc=0' \
  FAKE_MISSING_ITEMS="ItemA ItemB" -- "${P[@]}" A B
check "无法识别的错误：失败且不运行命令" \
  $'[ERROR] 2026/01/01 00:00:00 network is unreachable\nrc=1' \
  FAKE_OP_FAIL=1 -- "${P[@]}" A

printf 'export B="op://Other/ItemX/credential"\nC=plain value\nA="op://Agent/ItemC/credential"\n' >"$overlay"

check "覆盖层覆盖基座，明文原样" $'A=Agent/ItemC 的值\nB=Other/ItemX 的值\nC=plain value\nrc=0' -- "${P[@]}" A B C
check "vault 不可见：跳过该 vault 的全部引用，回落到基座" \
  $'⚠️ [sec-run] 跳过无法解析的引用 op://Other/（变量: B）\nA=Agent/ItemC 的值\nB=Agent/ItemB 的值\nC=plain value\nrc=0' \
  FAKE_MISSING_VAULTS=Other -- "${P[@]}" A B C
check "覆盖层条目不存在：回落到基座" \
  $'⚠️ [sec-run] 跳过无法解析的引用 op://Agent/ItemC/（变量: A）\nA=Agent/ItemA 的值\nB=Other/ItemX 的值\nrc=0' \
  FAKE_MISSING_ITEMS=ItemC -- "${P[@]}" A B

rm -f "$overlay"
check "无参数：用法" $'Usage: sec-run <command> [args...]\nrc=1' --

echo "pass=$pass fail=$fail"
((fail == 0))
