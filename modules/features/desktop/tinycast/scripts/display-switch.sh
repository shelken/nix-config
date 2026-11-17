#!/usr/bin/env bash

usage() {
  cat <<'EOF'
用法: display-switch <输入源>

切换 GE278UR 显示器输入源。
EOF
}

if [[ $# -eq 1 && ( "$1" == "-h" || "$1" == "--help" ) ]]; then
  usage
  exit 0
fi

if [[ $# -ne 1 ]]; then
  usage >&2
  exit 64
fi

input_source=$1
exec /Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay \
  set -name=GE278UR -vcp=inputSelect -ddc="$input_source"
