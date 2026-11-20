: "${AGENT_GH_OWNER:?}"

rules=("issue create" "issue new" "issue comment" "pr comment")

hit=0
for rule in "${rules[@]}"; do
  [[ "${1-} ${2-}" == "$rule" ]] && hit=1
done
((hit)) && [[ -n ${AGENT_GITHUB_TOKEN-} ]] || exec gh "$@"

owner_of_repo() {
  [[ $1 == */* ]] || return 0
  local head=${1%/*}
  echo "${head##*/}"
}

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
    gh repo view --json owner --jq .owner.login 2>/dev/null || true
  fi
}

owner=$(resolve_owner "$@")

if [[ -n $owner && ${owner,,} == "${AGENT_GH_OWNER,,}" ]]; then
  GH_TOKEN=$AGENT_GITHUB_TOKEN exec gh "$@"
fi
exec gh "$@"
