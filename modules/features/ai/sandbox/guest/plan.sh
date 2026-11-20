#!/usr/bin/env bash
set -euo pipefail

parse_plan() {
  local plan_json="$1"
  PLAN_PROJECT_ROOT="$(jq -r '.project_root' <<< "$plan_json")"
  PLAN_GIT_COMMON_DIR="$(jq -r '.git_common_dir // empty' <<< "$plan_json")"
  mapfile -t PLAN_DEFAULT_ALLOW < <(jq -r '.default_allow[]? // empty' <<< "$plan_json")
  mapfile -t PLAN_NETWORK < <(jq -r '.network[]? // empty' <<< "$plan_json")
  mapfile -t PLAN_IMPORT_STAGES < <(jq -r '[.imports[]? | [.stage, .dir]] | unique[] | @tsv' <<< "$plan_json")
  mapfile -t PLAN_PATHS < <(jq -r '.paths[]? | [.path, (.readonly // false | tostring)] | join("\t")' <<< "$plan_json")
}
