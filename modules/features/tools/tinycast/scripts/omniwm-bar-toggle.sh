#!/usr/bin/env bash
# 在 default（系统菜单栏 + 按住 Ctrl+Option 显示 spaces）与 full（OmniWM 通栏）之间切换 shell profile。
# 当前 profile 以 shell.toml 的 profile 键为准，OmniWM 切换时会写回这个键；没有该键即 default。
set -euo pipefail

current=$(sed -n 's/^profile *= *"\(.*\)"/\1/p' "$HOME/.config/omniwm/shell/shell.toml")

if [[ "$current" == "full" ]]; then
  next=default
else
  next=full
fi

exec /opt/homebrew/bin/omniwmctl shell profile "$next"
