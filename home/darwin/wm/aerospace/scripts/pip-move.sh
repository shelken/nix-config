#!/usr/bin/env bash
set -e
# Get current workspace
echo "change 2"
current_workspace=$(aerospace list-workspaces --focused)
# Move PiP windows to current workspace (handles both "Picture-in-Picture" and "Picture in Picture")
aerospace list-windows --all | grep -E "(\| Picture-in-Picture|\| Picture in Picture|\| 画中画|\| 访达)" | awk '{print $1}' | while read window_id; do
    if [ -n "$window_id" ]; then
        aerospace move-node-to-workspace --window-id "$window_id" "$current_workspace"
    fi
done