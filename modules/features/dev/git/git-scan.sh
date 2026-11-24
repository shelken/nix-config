#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: git-scan [options] [dir ...]

扫描指定目录或 Git 仓库，检查工作区干净度与分支合并状态（支持普通仓库与 worktree）。
不传目录时默认扫描当前目录。

Options:
  -w, --worktrees  审计 worktree（传入主仓库列全部关联 worktree，传入单个 worktree 仅审自身，传入目录递归扫描）
  --clean          审计并直接删除所有已合并且无残留的 worktree 与对应本地分支（隐含 -w）
  -a, --all        默认模式下同时列出干净的仓库
  --fetch          审计 worktree 前先对主仓库执行 git fetch origin --prune
  --debug          输出阶段耗时与判定路径
  -h, --help       显示帮助信息
EOF
}

MODE="repos"
DO_CLEAN=0
SHOW_ALL=0
DO_FETCH=0
DEBUG=0
dirs=()

while (( $# > 0 )); do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    -w|--worktrees)
      MODE="worktrees"
      shift
      ;;
    --clean)
      MODE="worktrees"
      DO_CLEAN=1
      shift
      ;;
    -a|--all)
      SHOW_ALL=1
      shift
      ;;
    --fetch)
      DO_FETCH=1
      shift
      ;;
    --debug)
      DEBUG=1
      shift
      ;;
    --)
      shift
      while (( $# > 0 )); do
        dirs+=("$1")
        shift
      done
      ;;
    -*)
      printf '未知选项: %s\n\n' "$1" >&2
      usage >&2
      exit 1
      ;;
    *)
      dirs+=("$1")
      shift
      ;;
  esac
done

if (( ${#dirs[@]} == 0 )); then
  dirs=("$(pwd)")
fi

if [[ -t 1 ]]; then
  RED=$'\033[0;31m'
  GREEN=$'\033[0;32m'
  YELLOW=$'\033[0;33m'
  CYAN=$'\033[0;36m'
  RESET=$'\033[0m'
else
  RED=""
  GREEN=""
  YELLOW=""
  CYAN=""
  RESET=""
fi

TMP_OBJ_DIR=""

cleanup_tmp() {
  if [[ -n $TMP_OBJ_DIR && -d $TMP_OBJ_DIR ]]; then
    rm -rf "$TMP_OBJ_DIR"
  fi
}
trap cleanup_tmp EXIT

format_path() {
  local p=$1
  if [[ $p == "$HOME"/* ]]; then
    printf '~%s' "${p#"$HOME"}"
  else
    printf '%s' "$p"
  fi
}

now_ms() {
  local ts
  ts=$(date +%s%3N 2>/dev/null || true)
  if [[ $ts =~ ^[0-9]+$ ]]; then
    printf '%s' "$ts"
  else
    printf '%s' "$((SECONDS * 1000))"
  fi
}

debug_log() {
  if (( DEBUG == 1 )); then
    printf '[debug] %s\n' "$*" >&2
  fi
}

is_linked_worktree() {
  local dir=$1
  [[ -f "$dir/.git" ]] || return 1
  local git_dir common_dir
  git_dir=$(git -C "$dir" rev-parse --path-format=absolute --git-dir 2>/dev/null || true)
  common_dir=$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
  [[ -n $git_dir && -n $common_dir && $git_dir != "$common_dir" && $git_dir == "$common_dir/worktrees/"* ]]
}

is_cache_ignored() {
  local f=$1
  local trimmed="${f%/}"
  local base="${trimmed##*/}"
  case "$base" in
    .DS_Store|.pre-commit-config.yaml|.host-profile|result|config.yml.lock|\
    __pycache__|.ruff_cache|.pytest_cache|.mypy_cache|.venv|venv|\
    .direnv|.idea|node_modules|target|.build|dist|build|.next|.turbo|.vite|.cache)
      return 0
      ;;
  esac
  case "$trimmed" in
    */__pycache__/*|__pycache__/*|*/.ruff_cache/*|.ruff_cache/*|\
    */.pytest_cache/*|.pytest_cache/*|*/.mypy_cache/*|.mypy_cache/*|\
    .venv/*|*/.venv/*|venv/*|*/venv/*|.direnv/*|*/.direnv/*|.idea/*|*/.idea/*|\
    node_modules/*|*/node_modules/*|target/*|*/target/*|.build/*|*/.build/*|\
    dist/*|*/dist/*|build/*|*/build/*|.next/*|*/.next/*|.turbo/*|*/.turbo/*|\
    .vite/*|*/.vite/*|.cache/*|*/.cache/*)
      return 0
      ;;
  esac
  return 1
}

resolve_main_repo() {
  local repo=$1
  local common_dir
  common_dir=$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
  if [[ -z $common_dir ]]; then
    return 0
  fi
  if [[ $common_dir == */.git ]]; then
    printf '%s' "${common_dir%/.git}"
  else
    printf '%s' "$common_dir"
  fi
}

detect_base_ref() {
  local repo=$1
  local ref
  ref=$(git -C "$repo" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)
  if [[ -n $ref ]] && git -C "$repo" rev-parse --verify --quiet "$ref" >/dev/null 2>&1; then
    printf '%s' "$ref"
    return 0
  fi
  for ref in origin/main origin/master main master; do
    if git -C "$repo" rev-parse --verify --quiet "$ref" >/dev/null 2>&1; then
      printf '%s' "$ref"
      return 0
    fi
  done
  return 0
}

merge_status() {
  local common_repo=$1
  local target=$2
  local base_ref=$3
  if [[ -z $base_ref || -z $target ]]; then
    printf 'unknown'
    return 0
  fi
  if git -C "$common_repo" merge-base --is-ancestor "$target" "$base_ref" 2>/dev/null; then
    printf 'ancestor'
    return 0
  fi
  local mb tree real_obj_dir dangling cherry
  mb=$(git -C "$common_repo" merge-base "$base_ref" "$target" 2>/dev/null || true)
  if [[ -n $mb ]]; then
    tree=$(git -C "$common_repo" rev-parse "${target}^{tree}" 2>/dev/null || true)
    real_obj_dir=$(git -C "$common_repo" rev-parse --path-format=absolute --git-path objects 2>/dev/null || true)
    if [[ -n $tree && -n $real_obj_dir && -n $TMP_OBJ_DIR ]]; then
      dangling=$(
        GIT_OBJECT_DIRECTORY="$TMP_OBJ_DIR" \
        GIT_ALTERNATE_OBJECT_DIRECTORIES="$real_obj_dir" \
        git -C "$common_repo" commit-tree "$tree" -p "$mb" -m "_" 2>/dev/null || true
      )
      if [[ -n $dangling ]]; then
        cherry=$(
          GIT_OBJECT_DIRECTORY="$TMP_OBJ_DIR" \
          GIT_ALTERNATE_OBJECT_DIRECTORIES="$real_obj_dir" \
          git -C "$common_repo" cherry "$base_ref" "$dangling" 2>/dev/null || true
        )
        if [[ $cherry == -* ]]; then
          printf 'squash'
          return 0
        fi
      fi
    fi
  fi
  printf 'unmerged'
}

fetched_repos=""

maybe_fetch_repo() {
  local repo=$1
  if (( DO_FETCH == 0 )); then
    return 0
  fi
  local common_dir
  common_dir=$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
  if [[ -z $common_dir ]]; then
    return 0
  fi
  case $'\n'"$fetched_repos"$'\n' in
    *$'\n'"$common_dir"$'\n'*)
      return 0
      ;;
  esac
  fetched_repos+=$'\n'"$common_dir"
  local t0 t1 fetch_err
  t0=$(now_ms)
  if ! fetch_err=$(git -C "$repo" fetch origin --prune 2>&1); then
    local label
    label=$(format_path "$repo")
    printf '%s⚠️  fetch 失败 (%s): %s%s\n' "$YELLOW" "$label" "${fetch_err%%$'\n'*}" "$RESET" >&2
  fi
  t1=$(now_ms)
  debug_log "fetch $common_dir: $((t1 - t0))ms"
}

found=0
clean=0
dirty=0

check_repo() {
  local repo=$1
  local label
  label=$(format_path "$repo")
  local kind=""
  if is_linked_worktree "$repo"; then
    kind=" ${CYAN}[wt]${RESET}"
  fi
  local issues=()

  local unstaged staged untracked
  unstaged=$(git -C "$repo" -c core.quotepath=false diff --name-only 2>/dev/null || true)
  staged=$(git -C "$repo" -c core.quotepath=false diff --cached --name-only 2>/dev/null || true)
  untracked=$(git -C "$repo" -c core.quotepath=false ls-files --others --exclude-standard 2>/dev/null || true)

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
  else
    issues+=("${YELLOW}处于 detached HEAD${RESET}")
  fi

  if (( ${#issues[@]} > 0 )); then
    printf '\n📁 %s%s\n' "$label" "$kind"
    local issue
    for issue in "${issues[@]}"; do
      printf '   • %s\n' "$issue"
    done
    dirty=$((dirty + 1))
  else
    if (( SHOW_ALL == 1 )); then
      printf '\n✅ %s%s (%s)\n' "$label" "$kind" "${branch:-detached}"
    fi
    clean=$((clean + 1))
  fi

  found=$((found + 1))
}

audited_worktrees=""
wt_total=0
wt_clean_lines=()
wt_clean_repos=()
wt_clean_paths=()
wt_clean_branches=()
wt_dirty_merged_lines=()
wt_keep_lines=()

audit_worktree() {
  local wt_path=$1
  local wt_branch=$2
  local wt_head=$3
  local wt_locked=$4
  local wt_prunable=$5
  local common_repo=$6
  local base_ref=$7

  local wt_key
  wt_key=$(realpath "$wt_path" 2>/dev/null || printf '%s' "$wt_path")
  case $'\n'"$audited_worktrees"$'\n' in
    *$'\n'"$wt_key"$'\n'*)
      return 0
      ;;
  esac
  audited_worktrees+=$'\n'"$wt_key"

  local label
  label=$(format_path "$wt_path")
  wt_total=$((wt_total + 1))

  if [[ $wt_prunable == "1" || ! -d $wt_path ]]; then
    wt_keep_lines+=("   • ${label}  (${wt_branch:-detached}) — ${YELLOW}目录已缺失，可 git worktree prune${RESET}")
    return 0
  fi

  if [[ -z $wt_branch ]]; then
    local short_head="${wt_head:0:8}"
    local mstate
    mstate=$(merge_status "$common_repo" "$wt_head" "$base_ref")
    wt_keep_lines+=("   • ${label}  (detached@${short_head}, ${mstate}) — ${YELLOW}detached HEAD${RESET}")
    return 0
  fi

  local base_short="${base_ref#origin/}"
  if [[ $wt_branch == "main" || $wt_branch == "master" || ( -n $base_short && $wt_branch == "$base_short" ) ]]; then
    wt_keep_lines+=("   • ${label}  (${CYAN}${wt_branch}${RESET}) — ${YELLOW}默认分支，不自动清理${RESET}")
    return 0
  fi

  local branch_ref="refs/heads/${wt_branch}"
  local mstate
  mstate=$(merge_status "$common_repo" "$branch_ref" "$base_ref")
  debug_log "wt=$label branch=$wt_branch base=$base_ref merge=$mstate"

  local reasons=()
  if [[ $wt_locked == "1" ]]; then
    reasons+=("locked")
  fi

  local unstaged staged untracked ignored
  unstaged=$(git -C "$wt_path" -c core.quotepath=false diff --name-only 2>/dev/null || true)
  staged=$(git -C "$wt_path" -c core.quotepath=false diff --cached --name-only 2>/dev/null || true)
  untracked=$(git -C "$wt_path" -c core.quotepath=false ls-files --others --exclude-standard 2>/dev/null || true)
  ignored=$(git -C "$wt_path" -c core.quotepath=false ls-files --others --ignored --exclude-standard --directory 2>/dev/null || true)

  if [[ -n $unstaged ]]; then
    reasons+=("未提交修改($(printf '%s\n' "$unstaged" | wc -l | tr -d ' '))")
  fi
  if [[ -n $staged ]]; then
    reasons+=("已暂存($(printf '%s\n' "$staged" | wc -l | tr -d ' '))")
  fi
  if [[ -n $untracked ]]; then
    reasons+=("未追踪文件($(printf '%s\n' "$untracked" | wc -l | tr -d ' '))")
  fi

  local non_cache_ignored=()
  local seen_non_cache=""
  if [[ -n $ignored ]]; then
    local ig sub_ig
    while IFS= read -r ig; do
      [[ -z $ig ]] && continue
      if is_cache_ignored "$ig"; then
        continue
      fi
      if [[ $ig == */ ]]; then
        while IFS= read -r sub_ig; do
          [[ -z $sub_ig ]] && continue
          if ! is_cache_ignored "$sub_ig"; then
            case $'\n'"$seen_non_cache"$'\n' in
              *$'\n'"$sub_ig"$'\n'*) ;;
              *)
                seen_non_cache+=$'\n'"$sub_ig"
                non_cache_ignored+=("$sub_ig")
                ;;
            esac
          fi
        done < <(git -C "$wt_path" -c core.quotepath=false ls-files --others --ignored --exclude-standard -- "$ig" 2>/dev/null || true)
      else
        case $'\n'"$seen_non_cache"$'\n' in
          *$'\n'"$ig"$'\n'*) ;;
          *)
            seen_non_cache+=$'\n'"$ig"
            non_cache_ignored+=("$ig")
            ;;
        esac
      fi
    done <<< "$ignored"
  fi
  if (( ${#non_cache_ignored[@]} > 0 )); then
    reasons+=("非缓存忽略残留(${non_cache_ignored[0]}${non_cache_ignored[1]:+, ...})")
  fi

  if [[ $mstate == "ancestor" || $mstate == "squash" ]]; then
    if (( ${#reasons[@]} == 0 )); then
      local main_repo
      main_repo=$(resolve_main_repo "$common_repo")
      wt_clean_lines+=("   • ${label}  (${CYAN}${wt_branch}${RESET}, ${mstate})")
      wt_clean_repos+=("$main_repo")
      wt_clean_paths+=("$wt_path")
      wt_clean_branches+=("$wt_branch")
    else
      local joined
      joined=$(IFS='、'; printf '%s' "${reasons[*]}")
      wt_dirty_merged_lines+=("   • ${label}  (${CYAN}${wt_branch}${RESET}, ${mstate}) — ${YELLOW}${joined}${RESET}")
    fi
  else
    local ahead="?"
    if [[ -n $base_ref ]]; then
      ahead=$(git -C "$common_repo" rev-list "${base_ref}..${branch_ref}" --count 2>/dev/null || echo "?")
    fi
    local detail="未合并(${ahead} commits)"
    if (( ${#reasons[@]} > 0 )); then
      local joined
      joined=$(IFS='、'; printf '%s' "${reasons[*]}")
      detail+="、${joined}"
    fi
    wt_keep_lines+=("   • ${label}  (${CYAN}${wt_branch}${RESET}) — ${RED}${detail}${RESET}")
  fi
}

audit_single_worktree() {
  local wt_path=$1
  maybe_fetch_repo "$wt_path"
  local base_ref branch head locked=0 gitdir_real
  base_ref=$(detect_base_ref "$wt_path")
  branch=$(git -C "$wt_path" symbolic-ref --short HEAD 2>/dev/null || true)
  head=$(git -C "$wt_path" rev-parse HEAD 2>/dev/null || true)
  gitdir_real=$(git -C "$wt_path" rev-parse --path-format=absolute --git-dir 2>/dev/null || true)
  if [[ -n $gitdir_real && -f "$gitdir_real/locked" ]]; then
    locked=1
  fi
  audit_worktree "$wt_path" "$branch" "$head" "$locked" 0 "$wt_path" "$base_ref"
}

audit_repo_worktrees() {
  local repo=$1
  maybe_fetch_repo "$repo"
  local base_ref
  base_ref=$(detect_base_ref "$repo")
  debug_log "repo=$repo base_ref=${base_ref:-none}"

  local idx=0
  local cur_path="" cur_head="" cur_branch="" cur_locked=0 cur_prunable=0
  local line
  while IFS= read -r line || [[ -n $cur_path ]]; do
    if [[ -z $line ]]; then
      if [[ -n $cur_path ]]; then
        if (( idx > 0 )); then
          audit_worktree "$cur_path" "$cur_branch" "$cur_head" "$cur_locked" "$cur_prunable" "$repo" "$base_ref"
        fi
        idx=$((idx + 1))
        cur_path=""
        cur_head=""
        cur_branch=""
        cur_locked=0
        cur_prunable=0
      fi
      [[ -z $line ]] && continue
    fi
    case "$line" in
      worktree\ *) cur_path="${line#worktree }" ;;
      HEAD\ *) cur_head="${line#HEAD }" ;;
      branch\ refs/heads/*) cur_branch="${line#branch refs/heads/}" ;;
      locked*) cur_locked=1 ;;
      prunable*) cur_prunable=1 ;;
    esac
  done < <(git -C "$repo" worktree list --porcelain; printf '\n')
}

audit_dir_worktrees() {
  local dir=$1
  local git_file
  while IFS= read -r git_file; do
    [[ -z $git_file ]] && continue
    local wt_path
    wt_path=$(dirname "$git_file")
    if ! is_linked_worktree "$wt_path"; then
      continue
    fi
    audit_single_worktree "$wt_path"
  done < <(
    find "$dir" \
      \( -name .git -type d -prune \) -o \
      \( \( -name node_modules -o -name target -o -name .venv -o -name venv -o -name .direnv -o -name .build -o -name dist -o -name __pycache__ \) -type d -prune \) -o \
      \( -name .git -type f -print \) 2>/dev/null | sort || true
  )
}

run_clean_worktrees() {
  local count=${#wt_clean_paths[@]}
  if (( count == 0 )); then
    return 0
  fi

  local cwd_real
  cwd_real=$(realpath "$(pwd)")
  local removed_wt=0 removed_br=0 failed=0
  local pruned_repos=""

  printf '\n%s🧹 开始清理（共 %d 个）%s\n' "$GREEN" "$count" "$RESET"

  local i main_repo wt_path wt_branch wt_real label err br_err br_note
  for ((i = 0; i < count; i++)); do
    main_repo=${wt_clean_repos[i]}
    wt_path=${wt_clean_paths[i]}
    wt_branch=${wt_clean_branches[i]}
    label=$(format_path "$wt_path")
    wt_real=$(realpath "$wt_path" 2>/dev/null || printf '%s' "$wt_path")

    if [[ $cwd_real == "$wt_real" || $cwd_real == "$wt_real"/* ]]; then
      printf '   • %s %s跳过：当前工作目录位于该 worktree 内%s\n' "$label" "$YELLOW" "$RESET"
      failed=$((failed + 1))
      continue
    fi

    if [[ -z $main_repo ]]; then
      printf '   • %s %s失败：无法解析主仓库%s\n' "$label" "$RED" "$RESET"
      failed=$((failed + 1))
      continue
    fi

    if err=$(git -C "$main_repo" worktree remove "$wt_path" 2>&1); then
      removed_wt=$((removed_wt + 1))
      br_note=""
      if br_err=$(git -C "$main_repo" branch -D "$wt_branch" 2>&1); then
        removed_br=$((removed_br + 1))
        br_note="，已删分支 ${wt_branch}"
      else
        br_note="，分支 ${wt_branch} 未删除（${br_err%%$'\n'*}）"
      fi
      printf '   • %s✅ %s%s%s\n' "$GREEN" "$label" "$br_note" "$RESET"

      case $'\n'"$pruned_repos"$'\n' in
        *$'\n'"$main_repo"$'\n'*) ;;
        *) pruned_repos+=$'\n'"$main_repo" ;;
      esac
    else
      printf '   • %s❌ %s — %s%s\n' "$RED" "$label" "$err" "$RESET"
      failed=$((failed + 1))
    fi
  done

  local r
  while IFS= read -r r; do
    [[ -z $r ]] && continue
    git -C "$r" worktree prune >/dev/null 2>&1 || true
    debug_log "pruned $r"
  done <<< "$pruned_repos"

  printf '\n清理汇总：已删 %d 个 worktree、%d 个本地分支，失败/跳过 %d 个\n' \
    "$removed_wt" "$removed_br" "$failed"
}

t_start=$(now_ms)

if [[ $MODE == "repos" ]]; then
  printf '🔍 扫描目录: %s\n' "${dirs[*]}"
  printf -- '----------------------------------------\n'

  for dir in "${dirs[@]}"; do
    if [[ ! -d $dir ]]; then
      printf '⚠️  目录不存在: %s\n' "$dir"
      continue
    fi
    resolved=$(realpath "$dir")
    while IFS= read -r git_entry; do
      [[ -z $git_entry ]] && continue
      check_repo "$(dirname "$git_entry")"
    done < <(
      find "$resolved" \
        \( -name .git -type d -prune -print \) -o \
        \( \( -name node_modules -o -name target -o -name .venv -o -name venv -o -name .direnv -o -name .build -o -name dist -o -name __pycache__ \) -type d -prune \) -o \
        \( -name .git -type f -print \) 2>/dev/null | sort || true
    )
  done

  printf '\n----------------------------------------\n'
  printf '共扫描 %d 个仓库：%d 个干净，%d 个需要注意\n' "$found" "$clean" "$dirty"
else
  TMP_OBJ_DIR=$(mktemp -d "${TMPDIR:-/tmp}/git-scan-obj.XXXXXX")

  printf '🔍 审计 worktrees: %s\n' "${dirs[*]}"
  printf -- '----------------------------------------\n'

  for dir in "${dirs[@]}"; do
    if [[ ! -d $dir ]]; then
      printf '⚠️  目录不存在: %s\n' "$dir"
      continue
    fi
    resolved=$(realpath "$dir")
    if git -C "$resolved" rev-parse --git-dir >/dev/null 2>&1; then
      toplevel=$(git -C "$resolved" rev-parse --show-toplevel 2>/dev/null || true)
      if [[ -n $toplevel ]] && is_linked_worktree "$toplevel"; then
        audit_single_worktree "$toplevel"
      else
        audit_repo_worktrees "$resolved"
      fi
    else
      audit_dir_worktrees "$resolved"
    fi
  done

  if (( ${#wt_clean_lines[@]} > 0 )); then
    printf '\n%s✅ 可清理（已合并且无残留，共 %d 个）%s\n' "$GREEN" "${#wt_clean_lines[@]}" "$RESET"
    printf '%s\n' "${wt_clean_lines[@]}"
  fi
  if (( ${#wt_dirty_merged_lines[@]} > 0 )); then
    printf '\n%s⚠️  已合并但有残留（共 %d 个，不自动清理）%s\n' "$YELLOW" "${#wt_dirty_merged_lines[@]}" "$RESET"
    printf '%s\n' "${wt_dirty_merged_lines[@]}"
  fi
  if (( ${#wt_keep_lines[@]} > 0 )); then
    printf '\n%s🔒 未合并或需人工确认（共 %d 个）%s\n' "$RED" "${#wt_keep_lines[@]}" "$RESET"
    printf '%s\n' "${wt_keep_lines[@]}"
  fi

  printf '\n----------------------------------------\n'
  printf '共审计 %d 个 worktree：%d 个可清理，%d 个已合并有残留，%d 个未合并/需确认\n' \
    "$wt_total" "${#wt_clean_lines[@]}" "${#wt_dirty_merged_lines[@]}" "${#wt_keep_lines[@]}"

  if (( DO_CLEAN == 1 )); then
    run_clean_worktrees
  fi
fi

t_end=$(now_ms)
debug_log "total: $((t_end - t_start))ms"
