#!/usr/bin/env bash
# guest/plan.sh: 执行计划 (Plan) 的唯一解析点
# 宿主 sb 产出 Plan JSON（字段定义在 py/sb/plan.py），launcher 的其余模块只读下面的变量，不碰 JSON。
# 改 Plan 字段时只需要同步这里，test_contract.py 用真实的 Plan 校验两边一致。
#
# parse_plan <plan_json> 一次读完并设置：
#   PLAN_PROJECT_ROOT    项目根
#   PLAN_GIT_COMMON_DIR  worktree 的 git common dir，没有则为空串
#   PLAN_DEFAULT_ALLOW   数组：sb.yaml 放行的宿主端口，形如 host:tcp:8317
#   PLAN_NETWORK         数组：放行的私网目标，IP 或 IP:端口
#   PLAN_IMPORT_STAGES   数组：每项 "<stage>\t<目标目录>"，按 stage 与目录去重
#   PLAN_PATHS           数组：每项 "<绝对路径>\t<true|false>"，false 表示可写
set -euo pipefail
# 变量由 launcher 与 netns.sh 在内嵌后使用
# shellcheck disable=SC2034

parse_plan() {
  local plan_json="$1"
  PLAN_PROJECT_ROOT="$(jq -r '.project_root' <<< "$plan_json")"
  PLAN_GIT_COMMON_DIR="$(jq -r '.git_common_dir // empty' <<< "$plan_json")"
  mapfile -t PLAN_DEFAULT_ALLOW < <(jq -r '.default_allow[]? // empty' <<< "$plan_json")
  mapfile -t PLAN_NETWORK < <(jq -r '.network[]? // empty' <<< "$plan_json")
  mapfile -t PLAN_IMPORT_STAGES < <(jq -r '[.imports[]? | [.stage, .dir]] | unique[] | @tsv' <<< "$plan_json")
  mapfile -t PLAN_PATHS < <(jq -r '.paths[]? | [.path, (.readonly // false | tostring)] | @tsv' <<< "$plan_json")
}
