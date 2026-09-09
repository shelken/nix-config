#!/usr/bin/env bash

usage() {
  cat <<'EOF'
用法: pb-type

将剪贴板内容按键盘输入到当前焦点窗口。
EOF
}

if [[ $# -eq 1 && ( "$1" == "-h" || "$1" == "--help" ) ]]; then
  usage
  exit 0
fi

if [[ $# -ne 0 ]]; then
  usage >&2
  exit 64
fi

exec /usr/bin/osascript -e 'tell application "System Events" to keystroke (the clipboard)'
