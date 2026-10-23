#!/usr/bin/env zsh
# git-check: 递归检查目录下所有 git 仓库的未提交/未推送状态
# 用法: git-check [目录] [目录2] ...
#       不传参数则检查当前目录

local dirs=("$@")
[[ ${#dirs} -eq 0 ]] && dirs=("$(pwd)")

local RED='\033[0;31m'
local YELLOW='\033[0;33m'
local GREEN='\033[0;32m'
local CYAN='\033[0;36m'
local BOLD='\033[1m'
local RESET='\033[0m'

local found=0
local clean=0
local dirty=0

_find_git_repos() {
    local base="$1"
    while IFS= read -r git_dir; do
        echo "${git_dir:h}"
    done < <(find "$base" -name ".git" -type d -prune 2>/dev/null)
}

_check_repo() {
    local repo="$1"
    local label="${repo/#$HOME/~}"

    local issues=()

    # 全部用 git -C，不 cd，不触发 direnv
    local unstaged staged untracked
    unstaged=$(git -C "$repo" diff --name-only 2>/dev/null)
    staged=$(git -C "$repo" diff --cached --name-only 2>/dev/null)
    untracked=$(git -C "$repo" ls-files --others --exclude-standard 2>/dev/null)

    [[ -n "$unstaged" ]] && issues+=("${RED}有未提交的修改${RESET}")
    [[ -n "$staged" ]] && issues+=("${YELLOW}有已 stage 未 commit 的文件${RESET}")
    [[ -n "$untracked" ]] && issues+=("${YELLOW}有未追踪文件${RESET}")

    local branch remote_branch ahead
    branch=$(git -C "$repo" symbolic-ref --short HEAD 2>/dev/null)
    if [[ -n "$branch" ]]; then
        remote_branch=$(git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name "@{u}" 2>/dev/null)
        if [[ -n "$remote_branch" ]]; then
            ahead=$(git -C "$repo" rev-list "${remote_branch}..HEAD" --count 2>/dev/null)
            [[ "$ahead" -gt 0 ]] && issues+=("${RED}有 ${ahead} 个 commit 未推送${RESET}")
        else
            local local_commits
            local_commits=$(git -C "$repo" rev-list HEAD --count 2>/dev/null)
            [[ "$local_commits" -gt 0 ]] && issues+=("${CYAN}无 remote upstream（本地 ${local_commits} commits）${RESET}")
        fi
    fi

    if [[ ${#issues} -gt 0 ]]; then
        echo ""
        echo "📁 ${label}"
        for issue in "${issues[@]}"; do
            echo "   • ${issue}"
        done
        ((dirty++))
    else
        ((clean++))
    fi

    ((found++))
}

echo "🔍 扫描目录: ${dirs[*]}"
echo "----------------------------------------"

for dir in "${dirs[@]}"; do
    dir="${dir:A}"
    if [[ ! -d "$dir" ]]; then
        echo "⚠️  目录不存在: $dir"
        continue
    fi
    while IFS= read -r repo; do
        _check_repo "$repo"
    done < <(_find_git_repos "$dir" | sort)
done

echo ""
echo "----------------------------------------"
echo "共扫描 ${found} 个仓库：${clean} 个干净，${dirty} 个需要注意"

unfunction _find_git_repos _check_repo 2>/dev/null
