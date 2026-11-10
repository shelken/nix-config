# gh 包装：三类写操作作用于 AGENT_GH_OWNER 名下的仓库时，改用 agent 专属 token。
# 其余调用原样交给真实 gh（PATH 上的下一个 gh，由 _package.nix 保证）。
# 输入：AGENT_GH_OWNER（owner 名，由 _package.nix 写入）、AGENT_GITHUB_TOKEN（agent 的 token）
: "${AGENT_GH_OWNER:?}"

# 规则表：命中清单与报错清单共用这一份
rules=("issue create" "issue new" "issue comment" "pr comment")

hit=0
for rule in "${rules[@]}"; do
  [[ "${1-} ${2-}" == "$rule" ]] && hit=1
done
((hit)) || exec gh "$@"

# [HOST/]OWNER/REPO -> OWNER；不含斜杠时无 owner
owner_of_repo() {
  [[ $1 == */* ]] || return 0
  local head=${1%/*}
  echo "${head##*/}"
}

# 目标仓库的 owner，来源按 gh 自己的优先级：issue/PR 链接 > -R/--repo > GH_REPO > 当前目录
# 链接里的仓库优先于 -R，gh 的 issue 查找就是这样处理（pkg/cmd/issue/shared/lookup.go）
resolve_owner() {
  local arg flag_repo="" next=0
  for arg in "${@:3}"; do
    if ((next)); then
      flag_repo=$arg
      next=0
      continue
    fi
    if [[ $arg =~ ^https?://[^/]+/([^/]+)/[^/]+/(issues|pull)/[0-9]+ ]]; then
      echo "${BASH_REMATCH[1]}"
      return 0
    fi
    case $arg in
      -R | --repo) next=1 ;;
      --repo=*) flag_repo=${arg#--repo=} ;;
      -R?*) flag_repo=${arg#-R} ;;
      *) ;;
    esac
  done
  if [[ -n $flag_repo ]]; then
    owner_of_repo "$flag_repo"
  elif [[ -n ${GH_REPO-} ]]; then
    owner_of_repo "$GH_REPO"
  else
    # 当前目录的仓库交给 gh 解析，它认 set-default、upstream 与改名重定向；
    # 解析失败时输出为空，真实 gh 自己会报同样的错
    gh repo view --json owner --jq .owner.login 2>/dev/null || true
  fi
}

owner=$(resolve_owner "$@")

if [[ -n $owner && ${owner,,} == "${AGENT_GH_OWNER,,}" ]]; then
  if [[ -z ${AGENT_GITHUB_TOKEN-} ]]; then
    {
      echo "agent-gh: 缺少 AGENT_GITHUB_TOKEN。"
      echo "对 $AGENT_GH_OWNER 的仓库执行以下操作必须使用 agent 专属 token:"
      printf '  gh %s\n' "${rules[@]}"
      echo "本次调用未执行。"
    } >&2
    exit 1
  fi
  GH_TOKEN=$AGENT_GITHUB_TOKEN exec gh "$@"
fi
exec gh "$@"
