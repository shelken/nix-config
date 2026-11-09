# 会话归档：把冷文件压缩（zstd）并加密（age）成 <名>.zst.age，校验无误后才删原文件。
# 配置全部来自环境变量，由 nix 包装注入：
#   SESSION_ARCHIVE_ROOTS     要扫描的目录，换行分隔，不存在的目录直接跳过
#   SESSION_ARCHIVE_DAYS      mtime 超过多少天算冷文件
#   SESSION_ARCHIVE_KEY_FILE  age 私钥文件，可含多把；加密给其中全部公钥，解密用其中任一把
set -euo pipefail

: "${SESSION_ARCHIVE_ROOTS?}" "${SESSION_ARCHIVE_DAYS:?}" "${SESSION_ARCHIVE_KEY_FILE:?}"
umask 077

usage() {
  cat >&2 <<'EOF'
用法:
  session-archive run [--dry-run]     归档全部根目录里的冷文件
  session-archive restore PATH...     解回原名并删除归档文件，mtime 为现在；PATH 为 .zst.age 文件或目录
  session-archive rekey [PATH...]     用密钥文件里的当前全部公钥重新加密归档文件；缺省为全部根目录
EOF
  exit 2
}

# 中断时清掉当前 .part：restore 的 .part 是明文，不能留在原目录
recipients=""
cur_part=""
cleanup() {
  if [ -n "$recipients" ]; then rm -f "$recipients"; fi
  if [ -n "$cur_part" ]; then rm -f "$cur_part"; fi
}
trap cleanup EXIT

load_recipients() {
  recipients=$(mktemp)
  age-keygen -y "$SESSION_ARCHIVE_KEY_FILE" >"$recipients"
}

cold_files() {
  local root
  while IFS= read -r root; do
    [ -d "$root" ] || continue
    find "$root" -type f -mmin "+$((SESSION_ARCHIVE_DAYS * 1440))" \
      ! -name .DS_Store ! -name '*.zst.age' ! -name '*.part' \
      ! -name '*.db' ! -name '*.db-*' ! -name '*.lock*' -print0
  done <<<"$SESSION_ARCHIVE_ROOTS"
}

archived_files() {
  local p root
  if [ $# -eq 0 ]; then
    while IFS= read -r root; do
      if [ -d "$root" ]; then find "$root" -type f -name '*.zst.age' -print0; fi
    done <<<"$SESSION_ARCHIVE_ROOTS"
    return
  fi
  for p in "$@"; do
    if [ -d "$p" ]; then find "$p" -type f -name '*.zst.age' -print0; else printf '%s\0' "$p"; fi
  done
}

check_targets() {
  local p
  for p in "$@"; do
    if [ -d "$p" ] || { [ -f "$p" ] && [[ $p == *.zst.age ]]; }; then continue; fi
    echo "不是归档文件或目录: $p" >&2
    return 1
  done
}

mib() { echo "$(($1 / 1048576)) MiB"; }

# 每一步都显式判断：函数在 || 上下文里被调用时 errexit 不生效
archive_one() {
  local f=$1 out="$1.zst.age" tmp="$1.zst.age.part"
  cur_part=$tmp
  if ! zstd -19 -T0 -q -c "$f" | age -R "$recipients" -o "$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  # 逐字节比对解密结果与原文件；原文件在压缩期间被改动也会在这里暴露
  if ! age -d -i "$SESSION_ARCHIVE_KEY_FILE" "$tmp" | zstd -d -q -c | cmp -s - "$f"; then
    rm -f "$tmp"
    return 1
  fi
  touch -r "$f" "$tmp"
  if ! mv -f "$tmp" "$out"; then
    rm -f "$tmp"
    return 1
  fi
  cur_part=""
  rm -f "$f"
}

cmd_run() {
  local dry=0 f n=0 failed=0 before=0 after=0 size asize
  case "${1:-}" in
    "") ;;
    --dry-run) dry=1 ;;
    *) usage ;;
  esac
  [ "$dry" -eq 1 ] || load_recipients

  while IFS= read -r -d '' f; do
    if ! size=$(wc -c <"$f"); then
      echo "无法读取，跳过: $f" >&2
      failed=$((failed + 1))
      continue
    fi
    if [ "$dry" -eq 1 ]; then
      n=$((n + 1))
      before=$((before + size))
      continue
    fi
    echo "归档: $f"
    if archive_one "$f"; then
      n=$((n + 1))
      before=$((before + size))
      asize=$(wc -c <"$f.zst.age") || asize=0
      after=$((after + asize))
    else
      echo "失败，原文件保留: $f" >&2
      failed=$((failed + 1))
    fi
  done < <(cold_files)

  if [ "$dry" -eq 1 ]; then
    echo "dry-run: ${n} 个冷文件，原始 $(mib "$before")；不写不删"
  else
    echo "完成: 归档 ${n} 个，失败 ${failed} 个，原始 $(mib "$before") -> $(mib "$after")"
  fi
  [ "$failed" -eq 0 ]
}

restore_one() {
  local a=$1 out=${1%.zst.age}
  local tmp="$out.part"
  if [ -e "$out" ]; then
    echo "目标已存在，跳过: $out" >&2
    return 1
  fi
  cur_part=$tmp
  if ! age -d -i "$SESSION_ARCHIVE_KEY_FILE" "$a" | zstd -d -q -c >"$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  if ! mv "$tmp" "$out"; then
    rm -f "$tmp"
    return 1
  fi
  cur_part=""
  rm -f "$a"
}

cmd_restore() {
  local f n=0 failed=0
  [ $# -gt 0 ] || usage
  check_targets "$@"
  while IFS= read -r -d '' f; do
    if restore_one "$f"; then
      echo "已还原: ${f%.zst.age}"
      n=$((n + 1))
    else
      echo "还原失败: $f" >&2
      failed=$((failed + 1))
    fi
  done < <(archived_files "$@")
  echo "完成: 还原 ${n} 个，失败 ${failed} 个"
  [ "$failed" -eq 0 ]
}

rekey_one() {
  local f=$1 tmp="$1.part"
  cur_part=$tmp
  if ! age -d -i "$SESSION_ARCHIVE_KEY_FILE" "$f" | age -R "$recipients" -o "$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  if ! cmp -s <(age -d -i "$SESSION_ARCHIVE_KEY_FILE" "$f") <(age -d -i "$SESSION_ARCHIVE_KEY_FILE" "$tmp"); then
    rm -f "$tmp"
    return 1
  fi
  touch -r "$f" "$tmp"
  if ! mv -f "$tmp" "$f"; then
    rm -f "$tmp"
    return 1
  fi
  cur_part=""
}

cmd_rekey() {
  local f n=0 failed=0
  check_targets "$@"
  load_recipients
  while IFS= read -r -d '' f; do
    if rekey_one "$f"; then
      n=$((n + 1))
    else
      echo "换钥失败: $f" >&2
      failed=$((failed + 1))
    fi
  done < <(archived_files "$@")
  echo "完成: 换钥 ${n} 个，失败 ${failed} 个"
  [ "$failed" -eq 0 ]
}

cmd=${1:-}
[ $# -eq 0 ] || shift
case "$cmd" in
  run) cmd_run "$@" ;;
  restore) cmd_restore "$@" ;;
  rekey) cmd_rekey "$@" ;;
  *) usage ;;
esac
