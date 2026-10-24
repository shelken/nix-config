#!/usr/bin/env zsh
# ==============================================================================
# 一次性迁移：把 ~/.specific.zsh 中的明文凭据迁入 1Password Personal vault
# 配合 ADR 0010（凭据基座与覆盖层）。迁移后 specific.zsh 清空为覆盖层空文件。
#
# 行为：
#   - 解析 export KEY=VALUE 行（# 注释行跳过），每键在 Personal 建一个
#     API Credential 条目（条目名 = 变量名，字段 credential）
#   - 重复执行安全：同名条目已存在时跳过（幂等）
#   - --dry-run 只打印计划，不写 vault
#   - 全部迁完后把 specific.zsh 清空为仅含说明注释的空文件（不删除文件）
#
# 用法：
#   zsh utils/script/migrate_specific_to_op.sh [--dry-run]
# ==============================================================================
set -euo pipefail

SPECIFIC_FILE="${SPECIFIC_ZSH:-$HOME/.specific.zsh}"
VAULT="Personal"
DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

command -v op >/dev/null 2>&1 || { echo "错误: 未安装 op CLI" >&2; exit 1; }
[[ -s "$SPECIFIC_FILE" ]] || { echo "specific.zsh 不存在或为空，无需迁移"; exit 0; }

# 收集 (key value) 对；zsh read 逐行，值里的等号/空格不受影响
typeset -a keys values
while IFS= read -r line; do
  [[ "$line" =~ '^[[:space:]]*#' || -z "${line// }" ]] && continue
  [[ "$line" =~ ^[[:space:]]*export[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]] || continue
  key="${match[1]}"
  value="${match[2]}"
  # 去掉 sec-env 写入时包裹的引号（单/双）
  [[ "$value" =~ ^\"(.*)\"$ ]] && value="${match[1]}"
  [[ "$value" =~ ^\'(.*)\'$ ]] && value="${match[1]}"
  keys+=("$key")
  values+=("$value")
done < "$SPECIFIC_FILE"

if (( ${#keys} == 0 )); then
  echo "specific.zsh 中没有可迁移的变量"
  exit 0
fi

echo "计划迁移 ${#keys} 个变量到 1Password ${VAULT}:"
for i in {1..${#keys}}; do
  echo "  ${keys[i]}"
done

if (( DRY_RUN )); then
  echo "(dry-run，未写入)"
  exit 0
fi

failed=()
for i in {1..${#keys}}; do
  key="${keys[i]}"
  # 幂等：同名条目已存在则跳过（迁移中断可重跑）
  if op item get "$key" --vault "$VAULT" >/dev/null 2>&1; then
    echo "跳过（已存在）: $key"
    continue
  fi
  # 值经 stdin 传入，不落 shell 历史（assignment 语法会记录命令行）
  if print -r -- "${values[i]}" | op item create \
      --category="API Credential" --title="$key" \
      --vault "$VAULT" credential=- >/dev/null; then
    echo "✅ 已创建: $key"
  else
    echo "❌ 失败: $key" >&2
    failed+=("$key")
  fi
done

if (( ${#failed} > 0 )); then
  echo "以下变量迁移失败，重跑脚本即可续传: ${failed[*]}" >&2
  exit 1
fi

# 清空为覆盖层空文件：保留文件本身（sec-run 会检查它是否存在）与用法说明
cat > "$SPECIFIC_FILE" <<'EOF'
# 覆盖层（ADR 0010）：临时覆盖基座值时写在这里，格式：
#   export KEY=op://Personal/<条目>/credential   # 推荐：切换备用账号
#   export KEY=明文值                             # 允许但不推荐
# 注释掉一行 = 回落到基座值（1Password 中该条目的值）
EOF
chmod 600 "$SPECIFIC_FILE"
echo "✅ 迁移完成，specific.zsh 已重置为空覆盖层"
