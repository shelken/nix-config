#!/usr/bin/env bash

usage() {
  cat <<'EOF'
Usage: git-scan [dir ...]

递归扫描指定目录下的所有 Git 仓库，列出未提交修改、未追踪文件、未推送提交或缺少 upstream 的仓库。
不传目录时默认扫描当前目录。

Options:
  -h, --help  显示帮助信息
EOF
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
  usage
  exit 0
fi

dirs=("$@")
if (( ${#dirs[@]} == 0 )); then
  dirs=("$(pwd)")
fi

RED=$'\033[0;31m'
YELLOW=$'\033[0;33m'
CYAN=$'\033[0;36m'
RESET=$'\033[0m'

found=0
clean=0
dirty=0

check_repo() {
  local repo=$1
  local label="${repo/#$HOME/~}"
  local issues=()

  local unstaged staged untracked
  unstaged=$(git -C "$repo" diff --name-only 2>/dev/null || true)
  staged=$(git -C "$repo" diff --cached --name-only 2>/dev/null || true)
  untracked=$(git -C "$repo" ls-files --others --exclude-standard 2>/dev/null || true)

  [[ -n $unstaged ]] && issues+=("${RED}有未提交的修改${RESET}")
  [[ -n $staged ]] && issues+=("${YELLOW}有已 stage 未 commit 的文件${RESET}")
  [[ -n $untracked ]] && issues+=("${YELLOW}有未追踪文件${RESET}")

  local branch remote_branch ahead local_commits
  branch=$(git -C "$repo" symbolic-ref --short HEAD 2>/dev/null || true)
  if [[ -n $branch ]]; then
    remote_branch=$(git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name "@{u}" 2>/dev/null || true)
    if [[ -n $remote_branch ]]; then
      ahead=$(git -C "$repo" rev-list "${remote_branch}..HEAD" --count 2>/dev/null || echo 0)
      if (( ahead > 0 )); then
        issues+=("${RED}有 ${ahead} 个 commit 未推送${RESET}")
      fi
    else
      local_commits=$(git -C "$repo" rev-list HEAD --count 2>/dev/null || echo 0)
      if (( local_commits > 0 )); then
        issues+=("${CYAN}无 remote upstream（本地 ${local_commits} commits）${RESET}")
      fi
    fi
  fi

  if (( ${#issues[@]} > 0 )); then
    printf '\n📁 %s\n' "$label"
    local issue
    for issue in "${issues[@]}"; do
      printf '   • %s\n' "$issue"
    done
    dirty=$((dirty + 1))
  else
    clean=$((clean + 1))
  fi

  found=$((found + 1))
}

printf '🔍 扫描目录: %s\n' "${dirs[*]}"
printf -- '----------------------------------------\n'

for dir in "${dirs[@]}"; do
  if [[ ! -d $dir ]]; then
    printf '⚠️  目录不存在: %s\n' "$dir"
    continue
  fi
  resolved=$(realpath "$dir")
  while IFS= read -r git_dir; do
    check_repo "$(dirname "$git_dir")"
  done < <(find "$resolved" -name ".git" -type d -prune 2>/dev/null | sort || true)
done

printf '\n----------------------------------------\n'
printf '共扫描 %d 个仓库：%d 个干净，%d 个需要注意\n' "$found" "$clean" "$dirty"
