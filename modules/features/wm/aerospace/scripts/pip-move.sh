#!/usr/bin/env bash
# set -e
current_workspace=$(aerospace list-workspaces --focused)

# Define window patterns as array
patterns=(
    "Picture-in-Picture"
    "Picture in Picture"
    "画中画"
    "Raycast"
    "Claude$"
)

# Build grep pattern from array
pip_patterns=$(
    IFS='|'
    echo "${patterns[*]/#/\\| }"
)

aerospace list-windows --all |
    grep -E "($pip_patterns)" |
    awk '{print $1}' |
    xargs -I {} aerospace move-node-to-workspace --window-id {} "$current_workspace"
