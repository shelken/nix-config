#!/usr/bin/env bash
# guest/layout.sh: 声明配置与可写根布局规划
# 职责：
# 1. 解析 writable-roots 与 declared-paths 发布清单
# 2. 映射数据盘可写根 (/data/home/<root>)
# 3. 钉扎祖先目录为挂载点，防止改名绕过只读配置
# 4. 生成 bubblewrap 挂载参数 (LAYOUT_ARGS)
set -euo pipefail

declare -A AGENT_ROOTS=()
LAYOUT_ARGS=()
MOUNT_POINTS=()

declared_dst() {
  local t="$1"
  if [[ "$t" == .config/* ]]; then
    printf '/data/xdg/config/%s\n' "${t#.config/}"
  else
    printf '%s/%s\n' "$HOME" "$t"
  fi
}

backing_of() {
  local path="$1" root
  for root in "${!AGENT_ROOTS[@]}"; do
    if [[ "$path" == "$root" || "$path" == "$root/"* ]]; then
      printf '%s%s\n' "${AGENT_ROOTS[$root]}" "${path#"$root"}"
      return 0
    fi
  done
  printf '%s\n' "$path"
}

mount_root_of() {
  local path="$1" root
  for root in "${!AGENT_ROOTS[@]}"; do
    if [[ "$path" == "$root" || "$path" == "$root/"* ]]; then
      printf '%s\n' "$root"
      return 0
    fi
  done
  if [[ "$path" == /data/* ]]; then
    printf '/data\n'
    return 0
  fi
  return 1
}

is_empty_placeholder() {
  local path="$1"
  [[ ! -L "$path" ]] || return 1
  if [[ -d "$path" ]]; then
    [[ -z "$(ls -A "$path" 2>/dev/null || true)" ]]
  elif [[ -f "$path" ]]; then
    [[ ! -s "$path" ]]
  else
    return 1
  fi
}

resolve_conflict() {
  local path="$1" want="$2" others="$3"
  if [[ "$others" -gt 0 ]]; then
    echo "[-] 错误: 数据盘路径冲突：$path（期望 $want，但存在不同类型的项），有其他上下文在运行，不自动覆盖以免破坏它们" >&2
    exit 1
  fi
  if is_empty_placeholder "$path"; then
    rm -rf "$path"
    return 0
  fi
  echo "[-] 错误: 数据盘路径冲突：$path（期望 $want，但存在非空项），清空该路径后重试" >&2
  exit 1
}

is_agent_layout_path() {
  local target="$1" p
  for p in "${MOUNT_POINTS[@]}"; do
    [[ "$target" == "$p" || "$target" == "$p/"* ]] && return 0
  done
  for p in "${!AGENT_ROOTS[@]}"; do
    [[ "$target" == "$p" || "$target" == "$p/"* ]] && return 0
  done
  return 1
}

require_published() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo "[-] 错误: 沙箱发布目录不完整（缺少 $file），重新发布配置后重试：just hm" >&2
    exit 1
  fi
}

prepare_declared_layout() {
  local others="$1" cfg list roots_file rel t dst src want root p a
  local -a ancestors=() binds=() uppers=()
  [[ -e /run/sandbox-config/current ]] || return 0
  cfg="$(readlink -f /run/sandbox-config/current)"
  list="$cfg/declared-paths"
  roots_file="$cfg/writable-roots"
  require_published "$list"
  require_published "$roots_file"

  LAYOUT_ARGS+=(--tmpfs "$HOME")
  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    root="$HOME/$rel"
    AGENT_ROOTS["$root"]="/data/home/$rel"
    mkdir -p "${AGENT_ROOTS[$root]}"
    p="${root%/*}"
    while [[ "$p" == "$HOME/"* ]]; do
      uppers+=("$p")
      p="${p%/*}"
    done
  done < "$roots_file"

  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    MOUNT_POINTS+=("$p")
    LAYOUT_ARGS+=(--dir "$p" --tmpfs "$p")
  done < <(printf '%s\n' "${uppers[@]}" | LC_ALL=C sort -u)

  for root in "${!AGENT_ROOTS[@]}"; do
    LAYOUT_ARGS+=(--bind "${AGENT_ROOTS[$root]}" "$root")
  done

  while IFS= read -r t; do
    [[ -n "$t" ]] || continue
    src="$cfg/$t"
    if [[ ! -e "$src" ]]; then
      echo "[-] 错误: 声明配置缺失：$src（发布目录不完整，重新发布后重试）" >&2
      exit 1
    fi
    dst="$(declared_dst "$t")"
    if ! root="$(mount_root_of "$dst")"; then
      echo "[-] 错误: 声明配置 $t 不在任何可写根或 .config/ 下（重新发布配置后重试：just hm）" >&2
      exit 1
    fi
    p="$(dirname "$dst")"
    while [[ "$p" != "$root" && "$p" != / ]]; do
      ancestors+=("$p")
      p="$(dirname "$p")"
    done
    if [[ -d "$src" ]]; then want="目录"; else want="文件"; fi
    a="$(backing_of "$dst")"
    if [[ -e "$a" || -L "$a" ]]; then
      if [[ -L "$a" ]] || { [[ "$want" == "目录" ]] && [[ ! -d "$a" ]]; } || { [[ "$want" == "文件" ]] && [[ -d "$a" ]]; }; then
        resolve_conflict "$a" "$want" "$others"
      fi
    fi
    binds+=(--ro-bind "$src" "$dst")
  done < "$list"

  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    a="$(backing_of "$p")"
    if [[ -L "$a" ]] || { [[ -e "$a" ]] && [[ ! -d "$a" ]]; }; then
      resolve_conflict "$a" "目录" "$others"
    fi
    mkdir -p "$a"
    LAYOUT_ARGS+=(--bind "$a" "$p")
  done < <(printf '%s\n' "${ancestors[@]}" | LC_ALL=C sort -u)
  LAYOUT_ARGS+=("${binds[@]}")
}
