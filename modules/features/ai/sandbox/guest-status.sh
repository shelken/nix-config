#!/usr/bin/env bash
# ==============================================================================
# guest 侧工具状态查询（由 sb status 在 VM 内执行）
#
# 只打印 TSV，JSON 组装在宿主侧做（避免多层引号嵌套）：
#   missing<TAB><工具名>    mise 未安装的工具
#
# 只报告缺失的 mise 工具，不检查插件安装状态（ADR 0005 决策 5）。
# 环境唯一来源：/run/sandbox-config/current/guest-env.sh（ADR 0004 决策 5）。
# 该文件或 mise.toml 缺失说明 VM 未挂载生成配置（例如单元 2 的一次性 VM），
# 没有声明任何工具 → 无缺失项，退出码 0。
# ==============================================================================
set -euo pipefail

CONFIG_DIR=/run/sandbox-config/current

if [[ ! -f "$CONFIG_DIR/mise.toml" ]]; then
  exit 0
fi

if [[ ! -f "$CONFIG_DIR/guest-env.sh" ]]; then
  echo "[-] 错误: 缺少 $CONFIG_DIR/guest-env.sh，无法确定工具环境" >&2
  exit 3
fi
# shellcheck source=/dev/null
source "$CONFIG_DIR/guest-env.sh"

if ! command -v mise >/dev/null 2>&1; then
  echo "[-] 错误: guest 内未找到 mise，无法查询缺失工具" >&2
  exit 3
fi

# mise ls --missing 失败必须让状态查询非零退出：
# 吞掉错误按空缺失列表继续会把「查询失败」伪装成「全部已装」
missing_json="$(mise ls --missing --json)" || {
  echo "[-] 错误: mise ls --missing 查询失败 (rc=$?)" >&2
  exit 3
}
missing_names="$(printf '%s' "$missing_json" | jq -r 'keys[]')" || {
  echo "[-] 错误: 解析 mise ls --missing 输出失败" >&2
  exit 3
}
while IFS= read -r t; do
  [[ -n "$t" ]] && printf 'missing\t%s\n' "$t"
done <<< "$missing_names"
