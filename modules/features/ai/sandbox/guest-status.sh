#!/usr/bin/env bash
# 每行一个缺失的 mise 工具名。只报告缺失的 mise 工具，不检查插件安装状态，原因见 README「设计决策」。
# mise 查询失败必须非零退出：吞掉错误按空缺失列表继续，会把「查询失败」伪装成「全部已装」。
set -euo pipefail

missing_json="$(mise ls --missing --json)"
jq -r 'keys[]' <<< "$missing_json"
