#!/usr/bin/env bash
# session-archive 端到端验证：临时目录 + 临时 age 密钥 + 改旧 mtime 的假会话，不碰真实数据。
# 依赖 PATH 里有 age、age-keygen、zstd；用法: bash e2e.sh
set -euo pipefail

# agent 环境里 PATH 上的 rm 被替换成回收站（ai/trash.nix），会搬走文件而不是删除，测试必须用系统 rm
export PATH="/bin:$PATH"

here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}
ok() { echo "ok: $*"; }

old_stamp() { date -d "$1 days ago" +%Y%m%d%H%M 2>/dev/null || date -v-"$1"d +%Y%m%d%H%M; }

root="$work/sessions"
missing="$work/not-exist"
keys="$work/keys.txt"
mkdir -p "$root/proj/artifacts"
age-keygen -o "$keys" 2>/dev/null

export SESSION_ARCHIVE_ROOTS="$root
$missing"
export SESSION_ARCHIVE_DAYS=30
export SESSION_ARCHIVE_KEY_FILE="$keys"
sa() { bash "$here/session-archive.sh" "$@"; }

secret="SECRET-MARKER-$RANDOM"
body() { seq 2000 | sed "s/^/$secret line /"; }
mk() { # mk <路径> <几天前>
  body >"$1"
  touch -t "$(old_stamp "$2")" "$1"
}
mk "$root/proj/old.jsonl" 40
mk "$root/proj/artifacts/old.md" 40
mk "$root/proj/.DS_Store" 40
mk "$root/proj/sessions.db" 40
mk "$root/proj/sessions.db-wal" 40
mk "$root/proj/old.jsonl.lock.os" 40
mk "$root/proj/new.jsonl" 1
cp "$root/proj/old.jsonl" "$work/old.jsonl.orig"

# 1. dry-run 不写不删
out=$(sa run --dry-run)
echo "$out" | grep -q "2 个冷文件" || fail "dry-run 应报告 2 个冷文件: $out"
[ -f "$root/proj/old.jsonl" ] && [ ! -e "$root/proj/old.jsonl.zst.age" ] || fail "dry-run 改动了文件"
ok "dry-run 只统计"

# 2. run 归档冷文件，新文件与 .DS_Store 不动，缺失目录静默跳过
sa run >/dev/null || fail "run 失败"
[ ! -e "$root/proj/old.jsonl" ] && [ -f "$root/proj/old.jsonl.zst.age" ] || fail "old.jsonl 未归档"
[ ! -e "$root/proj/artifacts/old.md" ] && [ -f "$root/proj/artifacts/old.md.zst.age" ] || fail "artifact 未归档"
for keep in new.jsonl .DS_Store sessions.db sessions.db-wal old.jsonl.lock.os; do
  [ -f "$root/proj/$keep" ] || fail "不该归档的文件被动了: $keep"
done
! grep -q "$secret" "$root/proj/old.jsonl.zst.age" || fail "归档文件含明文"
[ -n "$(find "$root/proj/old.jsonl.zst.age" -mmin +$((30 * 1440)))" ] || fail "归档文件 mtime 应保留原值"
ok "归档、跳过规则、mtime"

# 3. 再跑一次没有可归档文件，且不会重复归档 .zst.age
sa run | grep -q "归档 0 个" || fail "二次运行应无事可做"
ok "幂等"

# 4. restore 还原内容，mtime 为现在，随后不会被再次归档
sa restore "$root/proj/old.jsonl.zst.age" >/dev/null || fail "restore 失败"
cmp -s "$root/proj/old.jsonl" "$work/old.jsonl.orig" || fail "还原内容与原文件不一致"
[ ! -e "$root/proj/old.jsonl.zst.age" ] || fail "restore 后应删除归档文件"
[ -z "$(find "$root/proj/old.jsonl" -mmin +5)" ] || fail "还原文件 mtime 应为现在"
sa run | grep -q "归档 0 个" || fail "刚还原的文件不应被再次归档"
[ -f "$root/proj/old.jsonl" ] || fail "刚还原的文件被归档了"
ok "restore 与 mtime"

# 5. restore 拒绝覆盖已存在文件；非法目标报错
mk "$root/proj/artifacts/other.md" 40
sa run >/dev/null
echo occupied >"$root/proj/artifacts/other.md"
if sa restore "$root/proj/artifacts/other.md.zst.age" 2>/dev/null; then fail "目标已存在时 restore 应失败"; fi
[ -f "$root/proj/artifacts/other.md.zst.age" ] && [ "$(cat "$root/proj/artifacts/other.md")" = occupied ] || fail "restore 不应改动已存在文件与归档"
if sa restore "$work/nope.txt" 2>/dev/null; then fail "非法目标应报错"; fi
ok "restore 拒绝覆盖与非法目标"

# 6. 校验失败：原文件保留、无残留、退出码非零
mkdir "$work/shim"
cat >"$work/shim/zstd" <<EOF
#!/usr/bin/env bash
for a in "\$@"; do [ "\$a" = -d ] && { echo garbage; exit 0; }; done
exec "$(command -v zstd)" "\$@"
EOF
chmod +x "$work/shim/zstd"
mk "$root/proj/bad.jsonl" 40
if PATH="$work/shim:$PATH" sa run 2>/dev/null; then fail "校验失败时 run 应非零退出"; fi
[ -f "$root/proj/bad.jsonl" ] || fail "校验失败时原文件必须保留"
[ -z "$(find "$root" -name 'bad.jsonl.*')" ] || fail "校验失败后不应残留归档或临时文件"
ok "校验失败保留原文件"

# 6b. mv 失败：run 保留原文件；restore 保留归档文件；都不留 .part
mkdir "$work/shim-mv"
printf '#!/bin/sh\nexit 1\n' >"$work/shim-mv/mv"
chmod +x "$work/shim-mv/mv"
mk "$root/proj/mvfail.jsonl" 40
if PATH="$work/shim-mv:$PATH" sa run 2>/dev/null; then fail "mv 失败时 run 应非零退出"; fi
[ -f "$root/proj/mvfail.jsonl" ] || fail "mv 失败时原文件必须保留"
[ -z "$(find "$root" -name 'mvfail.jsonl.*')" ] || fail "mv 失败后不应残留归档或 .part"
sa run >/dev/null
if PATH="$work/shim-mv:$PATH" sa restore "$root/proj/mvfail.jsonl.zst.age" 2>/dev/null; then fail "mv 失败时 restore 应非零退出"; fi
[ -f "$root/proj/mvfail.jsonl.zst.age" ] || fail "mv 失败时归档文件必须保留"
[ ! -e "$root/proj/mvfail.jsonl.part" ] || fail "restore 失败后不应残留明文 .part"
ok "mv 失败不丢数据"

# 6c. 单个文件不可读不中断其余文件
mk "$root/proj/locked.jsonl" 40
chmod 000 "$root/proj/locked.jsonl"
mk "$root/proj/after.jsonl" 40
if sa run 2>/dev/null; then fail "有不可读文件时 run 应非零退出"; fi
[ -f "$root/proj/after.jsonl.zst.age" ] || fail "不可读文件不应阻断其余文件的归档"
[ -f "$root/proj/locked.jsonl" ] || fail "不可读文件应保留"
chmod 600 "$root/proj/locked.jsonl"
ok "不可读文件不阻断其余"

# 6d. 还原中途被终止：明文 .part 不能留在原目录
mkdir "$work/shim-slow"
cat >"$work/shim-slow/zstd" <<EOF
#!/usr/bin/env bash
sleep 2
exec "$(command -v zstd)" "\$@"
EOF
chmod +x "$work/shim-slow/zstd"
mk "$root/proj/intr.jsonl" 40
sa run >/dev/null
PATH="$work/shim-slow:$PATH" bash "$here/session-archive.sh" restore "$root/proj/intr.jsonl.zst.age" >/dev/null 2>&1 &
pid=$!
for _ in $(seq 50); do [ -e "$root/proj/intr.jsonl.part" ] && break; sleep 0.1; done
[ -e "$root/proj/intr.jsonl.part" ] || fail "未观察到 restore 的 .part，用例失效"
kill -TERM "$pid"
wait "$pid" || true
[ ! -e "$root/proj/intr.jsonl.part" ] || fail "被终止后不应残留 .part"
[ -f "$root/proj/intr.jsonl.zst.age" ] || fail "被终止后归档文件必须保留"
ok "中断不留明文 .part"

# 7. 换钥：加入第二把私钥后 rekey，只保留新私钥仍可 restore
sa run >/dev/null # 把 bad.jsonl 正常归档
age-keygen 2>/dev/null >"$work/new-key.txt"
cat "$work/new-key.txt" >>"$keys"
sa rekey >/dev/null || fail "rekey 失败"
export SESSION_ARCHIVE_KEY_FILE="$work/new-key.txt"
sa restore "$root/proj/bad.jsonl.zst.age" >/dev/null || fail "rekey 后新私钥应能解密"
cmp -s "$root/proj/bad.jsonl" <(body) || fail "rekey 后内容不一致"
ok "rekey 与密钥轮换"

echo "ALL PASSED"
