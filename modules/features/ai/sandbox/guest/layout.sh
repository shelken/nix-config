#!/usr/bin/env bash
set -euo pipefail

declare -A AGENT_ROOTS=()
LAYOUT_ARGS=()
MOUNT_POINTS=()

# 用 nameref（$1）回写结果而不用 $(...)：microVM 里约 170 个声明路径，命令替换 fork 会拖慢启动约 1.5 秒
declared_dst() {
  local -n _out_dst="$1"
  local _l_t="$2"
  if [[ "$_l_t" == .config/* ]]; then
    _out_dst="$XDG_CONFIG_HOME/${_l_t#.config/}"
  else
    _out_dst="$HOME/$_l_t"
  fi
}

backing_of() {
  local -n _out_backing="$1"
  local _l_path="$2" _l_root
  for _l_root in "${!AGENT_ROOTS[@]}"; do
    if [[ "$_l_path" == "$_l_root" || "$_l_path" == "$_l_root/"* ]]; then
      _out_backing="${AGENT_ROOTS[$_l_root]}${_l_path#"$_l_root"}"
      return 0
    fi
  done
  _out_backing="$_l_path"
}

mount_root_of() {
  local -n _out_root="$1"
  local _l_path="$2" _l_root
  for _l_root in "${!AGENT_ROOTS[@]}"; do
    if [[ "$_l_path" == "$_l_root" || "$_l_path" == "$_l_root/"* ]]; then
      _out_root="$_l_root"
      return 0
    fi
  done
  if [[ "$_l_path" == "$SB_DATA_DIR"/* ]]; then
    _out_root="$SB_DATA_DIR"
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
  if is_empty_placeholder "$path" && [[ "$others" -eq 0 ]]; then
    rm -rf "$path"
    return 0
  fi
  if is_empty_placeholder "$path"; then
    echo "[-] 错误: 声明配置的落点 $path 残留了类型不符的空占位（需要$want），但还有 $others 个上下文在运行，可能正把它当挂载点用；全部退出后重试" >&2
  else
    echo "[-] 错误: 声明配置的落点 $path 已有类型不符的内容（需要$want），不会自动删除；确认无用后手动移走" >&2
  fi
  exit 1
}

reject_reserved_target() {
  local target="$1" p
  case "$target" in
    "$HOME" | / | /usr | /usr/* | /bin | /bin/* | /lib | /lib/* | /lib64 | /lib64/* | /etc | /etc/* | \
      /proc | /proc/* | /dev | /dev/* | /run | /run/* | /nix | /nix/* | /opt | /opt/* | \
      "$SB_DATA_DIR" | "$SB_DATA_DIR"/* | /.msb | /.msb/*)
      echo "[-] 错误: imports 的目标目录 $target 是沙箱保留位置" >&2
      exit 1
      ;;
  esac
  for p in "${MOUNT_POINTS[@]}" "${!AGENT_ROOTS[@]}"; do
    if [[ "$target" == "$p" || "$target" == "$p/"* ]]; then
      echo "[-] 错误: imports 的目标目录 $target 是沙箱保留位置" >&2
      exit 1
    fi
  done
}

require_published() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo "[-] 错误: 发布目录缺少清单：$file（发布目录来自旧版本，重新发布配置后重试：just hm）" >&2
    exit 1
  fi
}

LAYOUT_STATE="$SB_DATA_DIR/home/.declared-paths"
prune_stale_placeholders() {
  local others="$1" list="$2" t dst="" a="" _root=""
  local -a previous=()
  [[ "$others" -eq 0 ]] || return 0
  if [[ -f "$LAYOUT_STATE" ]]; then
    previous=("$LAYOUT_STATE")
  else
    previous=("$SB_CONFIG_MOUNT"/v*/declared-paths)
  fi
  while IFS= read -r t; do
    [[ -n "$t" ]] || continue
    declared_dst dst "$t"
    mount_root_of _root "$dst" || continue
    backing_of a "$dst"
    if [[ -e "$a" ]] && is_empty_placeholder "$a"; then
      rm -rf "$a"
    fi
  done < <(LC_ALL=C comm -23 <(cat "${previous[@]}" 2>/dev/null | LC_ALL=C sort -u) <(LC_ALL=C sort -u "$list"))
  mkdir -p "${LAYOUT_STATE%/*}"
  cp "$list" "$LAYOUT_STATE.tmp"
  mv "$LAYOUT_STATE.tmp" "$LAYOUT_STATE"
}

prepare_declared_layout() {
  local others="$1" cfg list roots_file rel t dst="" src want root="" p a=""
  local -a ancestors=() binds=() uppers=()
  cfg="$(readlink -f "$SB_CONFIG_DIR")"
  list="$cfg/declared-paths"
  roots_file="$cfg/writable-roots"
  require_published "$list"
  require_published "$roots_file"

  LAYOUT_ARGS+=(--tmpfs "$HOME")
  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    root="$HOME/$rel"
    AGENT_ROOTS["$root"]="$SB_DATA_DIR/home/$rel"
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
  prune_stale_placeholders "$others" "$list"

  while IFS= read -r t; do
    [[ -n "$t" ]] || continue
    src="$cfg/$t"
    if [[ ! -e "$src" ]]; then
      echo "[-] 错误: 声明配置缺失：$src（发布目录不完整，重新发布后重试）" >&2
      exit 1
    fi
    declared_dst dst "$t"
    if ! mount_root_of root "$dst"; then
      echo "[-] 错误: 声明配置 $t 不在任何可写根或 .config/ 下（发布清单不一致，重新发布配置后重试：just hm）" >&2
      exit 1
    fi
    p="${dst%/*}"
    p="${p:-/}"
    while [[ "$p" != "$root" && "$p" != / ]]; do
      ancestors+=("$p")
      p="${p%/*}"
      p="${p:-/}"
    done
    if [[ -d "$src" ]]; then want="目录"; else want="文件"; fi
    backing_of a "$dst"
    if [[ -e "$a" || -L "$a" ]]; then
      if [[ -L "$a" ]] || { [[ "$want" == "目录" ]] && [[ ! -d "$a" ]]; } || { [[ "$want" == "文件" ]] && [[ -d "$a" ]]; }; then
        resolve_conflict "$a" "$want" "$others"
      fi
    fi
    binds+=(--ro-bind "$src" "$dst")
  done < "$list"

  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    backing_of a "$p"
    if [[ -L "$a" ]] || { [[ -e "$a" ]] && [[ ! -d "$a" ]]; }; then
      resolve_conflict "$a" "目录" "$others"
    fi
    mkdir -p "$a"
    LAYOUT_ARGS+=(--bind "$a" "$p")
  done < <(printf '%s\n' "${ancestors[@]}" | LC_ALL=C sort -u)
  LAYOUT_ARGS+=("${binds[@]}")
}
