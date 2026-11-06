#!/usr/bin/env bash
# 缺失的 mise 工具，每行一个：missing<TAB><工具名>。JSON 组装在宿主侧做（避免多层引号嵌套）。
# 只报告缺失的 mise 工具，不检查插件安装状态，原因见 README「设计决策」。
# 环境由 _guest.nix 的包装加载 guest-env.sh。
# mise 查询失败必须非零退出：吞掉错误按空缺失列表继续，会把「查询失败」伪装成「全部已装」。
set -euo pipefail

missing_json="$(mise ls --missing --json)"
jq -r 'keys[] | "missing\t\(.)"' <<< "$missing_json"
