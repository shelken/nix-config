# sec-run：把凭据解析进环境后运行目标命令
# 输入（由 secrets.nix 写入）：SEC_RUN_BASE 基座环境文件、SEC_RUN_TOKEN_FILE service account token 文件
if (( $# == 0 )); then
  echo "Usage: sec-run <command> [args...]" >&2
  exit 1
fi

SPECIFIC_ZSH="$HOME/.specific.zsh"

# 环境文件里的变量名
key_names() {
  sed -nE 's/^[[:space:]]*(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)=.*/\2/p' "$@" 2>/dev/null | sort -u
}

typeset -a _sources
_sources=( "$SEC_RUN_BASE" )
[[ -s "$SPECIFIC_ZSH" ]] && _sources+=( "$SPECIFIC_ZSH" )

if [[ -n "${SEC_RUN_VERBOSE:-}" ]]; then
  print -u2 -- "🔐 [sec-run] 基座: $SEC_RUN_BASE"
  [[ -s "$SPECIFIC_ZSH" ]] && print -u2 -- "🔐 [sec-run] 覆盖层: $SPECIFIC_ZSH"
  print -u2 -- "🔐 [sec-run] 变量: ${(j: :)${(f)"$(key_names $_sources)"}}"
fi

# 无 op：直接 source 覆盖层，然后执行
if ! command -v op >/dev/null 2>&1; then
  [[ -s "$SPECIFIC_ZSH" ]] && source "$SPECIFIC_ZSH"
  exec "$@"
fi

# 先让 op 把值解析回本进程，再自己 exec 目标命令，而不是 exec op run：
# - op run 遇到一条解析不了的引用就整体失败，只有留在本进程才能剔除它后重试
# - service account token 只出现在 op 那一次调用里，不会留给目标命令
#   （留下会让其中所有 op 调用都被限制在 Agent vault）
# - 目标命令直接拿到终端，不经 op run 代理（代理会破坏 TUI 的 tty 探测与 SIGWINCH）
_work=$(mktemp -d) || exit 1
trap 'rm -rf "$_work"' EXIT
trap 'exit 130' INT TERM
typeset -a _skip # 已剔除的引用前缀，如 op://Agent/ITEM/

# 跑一次 op run，把解析后的 KEY=VALUE 以 NUL 分隔写到 stdout
resolve() {
  local -a files keys
  local src copy pat
  local -i n=0
  for src in $_sources; do
    if (( $#_skip )); then
      # 剔除只发生在副本上；副本可能含覆盖层的明文值，放在 0700 的临时目录里
      copy="$_work/env.$((++n))"
      local -a pats=()
      for pat in $_skip; do pats+=( -e "$pat" ); done
      grep -vF "${pats[@]}" -- "$src" >"$copy"
      src=$copy
    fi
    files+=( --env-file="$src" )
  done
  keys=( ${(f)"$(key_names ${files#--env-file=})"} )
  (
    # service account：op 见到 token 就不找桌面 App，没有 Touch ID 弹窗，
    # 无人值守的 agent 任务与 SSH 会话都能解析
    [[ -r "$SEC_RUN_TOKEN_FILE" ]] && export OP_SERVICE_ACCOUNT_TOKEN="$(<"$SEC_RUN_TOKEN_FILE")"
    # --no-masking：值要原样从 stdout 取回，默认的遮蔽会把它们换成占位文字
    exec op run --no-masking "${files[@]}" -- /bin/sh -c \
      'for k in "$@"; do eval "[ \"\${$k+x}\" ]" && { eval "v=\$$k"; printf "%s=%s\0" "$k" "$v"; }; done; :' _ "${keys[@]}"
  ) 2>"$_work/err"
}

# 从 op 的报错里认出解析不了的引用：条目名或带引号的 vault 名出现在报错文本中。
# 认不出就不猜（断网、token 失效等），交给调用方整体失败
culprits() {
  local err=" $1 " ref vault item
  local -a refs found
  refs=( ${(f)"$(grep -ohE 'op://[^/"]+/[^/"]+/' -- ${@:2} 2>/dev/null | sort -u)"} )
  for ref in $refs; do
    item=${${ref#op://*/}%/}
    [[ $err == *[^A-Za-z0-9_-]${(b)item}[^A-Za-z0-9_-]* ]] && found+=( $ref )
  done
  if (( ! $#found )); then
    for ref in $refs; do
      vault=${${ref#op://}%%/*}
      [[ $err == *\"${(b)vault}\"* ]] && found+=( "op://$vault/" )
    done
  fi
  print -rl -- ${(u)found}
}

typeset _out _err
while true; do
  _out=$(resolve) && break
  _err=$(<"$_work/err")
  typeset -a _current _bad
  _current=( $_sources )
  (( $#_skip )) && _current=( "$_work"/env.*(N) )
  _bad=( ${(f)"$(culprits "$_err" $_current)"} )
  if (( ! $#_bad )); then
    print -u2 -r -- "$_err"
    exit 1
  fi
  for _ref in $_bad; do
    print -u2 -- "⚠️ [sec-run] 跳过无法解析的引用 $_ref（变量: ${(j:, :)${(f)"$(grep -hF -- "$_ref" $_current | key_names)"}}）"
  done
  _skip+=( $_bad )
done
[[ -s "$_work/err" ]] && cat "$_work/err" >&2
# exec 不触发 EXIT trap，这里手动清理
rm -rf "$_work"
trap - EXIT INT TERM

for _kv in "${(@0)_out}"; do
  [[ -n $_kv ]] && export "$_kv"
done
unset _out _kv
exec "$@"
