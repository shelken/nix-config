#!/usr/bin/env bash
set -euo pipefail

missing_json="$(mise ls --missing --json)"
jq -r 'keys[]' <<< "$missing_json"
