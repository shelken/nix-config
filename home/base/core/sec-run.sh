#!/usr/bin/env zsh
# sec-run — secret 统一注入入口
# 数据占位符由 secrets.nix 的 replaceStrings 在 Nix 期填充, 运行期只读渲染文件, 零解密操作
typeset -A SEC_PROFILE_ALLOW=(
@PROFILE_ENTRIES@
)
typeset -A SEC_SECRET_PATH=(
@SECRET_PATH_ENTRIES@
)
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/sec-run"
DEFAULT_TTL="24h"

usage() {
  print -u2 -- "用法:"
  print -u2 -- "  sec-run <cmd> [args...]                            人类模式: 注入全部已声明 secret"
  print -u2 -- "  sec-run --agent=<profile> [--ttl <dur>] -- <cmd>   agent 模式: 仅注入该 profile 白名单变量"
  print -u2 -- "  sec-run --list                                     列出各模式可见变量名(不含值)"
  print -u2 -- "可用 profile: ${(j:, :)${(k)SEC_PROFILE_ALLOW}}"
}

ttl_to_seconds() {
  case "$1" in
    (<->s) print -- $(( ${1%s} ));;
    (<->m) print -- $(( ${1%m} * 60 ));;
    (<->h) print -- $(( ${1%h} * 3600 ));;
    (<->d) print -- $(( ${1%d} * 86400 ));;
    (*) return 1;;
  esac
}

cmd_args=()
agent_profile=""
ttl_arg=""
mode="run"
while (( $# > 0 )); do
  case "$1" in
    (--agent=*) agent_profile="${1#--agent=}"; shift;;
    (--agent) agent_profile="$2"; shift 2;;
    (--ttl) ttl_arg="$2"; shift 2;;
    (--list) mode="list"; shift;;
    (--help|-h) usage; exit 0;;
    (--) shift; cmd_args+=("$@"); break;;
    (*) cmd_args+=("$@"); shift;;
  esac
done

if [[ $mode == list ]]; then
  print "human: ${(j:, :)${(k)SEC_SECRET_PATH}}"
  for p in ${(k)SEC_PROFILE_ALLOW}; do
    print -- "$p: ${SEC_PROFILE_ALLOW[$p]}"
  done
  exit 0
fi

if [[ -n $agent_profile ]]; then
  allow="${SEC_PROFILE_ALLOW[$agent_profile]-}"
  if [[ -z $allow ]]; then
    print -u2 -- "sec-run: 未知 agent profile '$agent_profile', 可用: ${(j:, :)${(k)SEC_PROFILE_ALLOW}}"
    exit 1
  fi
  if ! secs=$(ttl_to_seconds "${ttl_arg:-$DEFAULT_TTL}"); then
    print -u2 -- "sec-run: 无效 --ttl '$ttl_arg' (支持 30m/2h/1d 这类形式)"
    exit 1
  fi
  mkdir -p "$STATE_DIR"
  grant_file="$STATE_DIR/$agent_profile.grant"
  now=$(date +%s)
  if [[ -n $ttl_arg ]]; then
    print $(( now + secs )) >| "$grant_file"
  elif [[ ! -s $grant_file || $(<"$grant_file") -le $now ]]; then
    print -u2 -- "sec-run: profile '$agent_profile' 无有效授权, 显式续期: sec-run --agent=$agent_profile --ttl $DEFAULT_TTL -- <cmd>"
    exit 1
  fi

  # 白名单外不留任何可能从父 shell 继承的已声明 secret 变量
  for v in ${(k)SEC_SECRET_PATH}; do unset "$v"; done
  injected=()
  for v in ${(s: :)allow}; do
    p="${SEC_SECRET_PATH[$v]-}"
    if [[ -n $p && -r $p ]]; then
      export "$v=$(<"$p")"
      injected+=("$v")
    else
      print -u2 -- "sec-run: 变量 $v 的渲染文件不可读, 检查该 secret 是否在 secretEnvMap 声明"
    fi
  done
  print -r -- "$(date -u +%FT%TZ) agent=$agent_profile vars=${(j:, :)injected:-none} cmd=${(j: :)cmd_args}" >> "$STATE_DIR/audit.log"
  if (( $#cmd_args == 0 )); then
    print -u2 -- "sec-run: agent 模式缺少要执行的命令"
    exit 1
  fi
  exec ${cmd_args[@]}
fi

if (( $#cmd_args == 0 )); then
  usage
  exit 1
fi

# 人类模式: 注入全部已声明 secret
typeset -a _before_vars
if [[ -n "${SEC_RUN_VERBOSE:-}" ]]; then
  _before_vars=( ${(k)parameters[(R)*export*]} )
fi
for v in ${(k)SEC_SECRET_PATH}; do
  p=$SEC_SECRET_PATH[$v]
  [[ -r $p ]] && export "$v=$(<"$p")"
done
if [[ -f ~/.specific.zsh ]]; then
  print -u2 -- "⚠️ [sec-run] ~/.specific.zsh 已停止加载, 按 docs/user-guide/02-secrets.md 迁移后删除"
fi
if [[ -n "${SEC_RUN_VERBOSE:-}" ]]; then
  typeset -a _after_vars _new_vars
  _after_vars=( ${(k)parameters[(R)*export*]} )
  _new_vars=( ${(ou)${_after_vars:|_before_vars}} )
  if (( ${#_new_vars} > 0 )); then
    print -u2 -- "🔐 [sec-run] 注入环境变量 (${#_new_vars} 个): ${(j:, :)_new_vars}"
  fi
fi
exec ${cmd_args[@]}
