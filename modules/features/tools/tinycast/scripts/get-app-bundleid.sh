#!/usr/bin/env bash

usage() {
  cat <<'EOF'
用法: get-app-bundleid

复制当前前台应用的 Bundle ID 到剪贴板，并弹窗提示 2 秒。
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

exec /usr/bin/osascript -e '
  tell application "System Events" to set frontAppId to bundle identifier of first process whose frontmost is true
  set the clipboard to frontAppId
  tell application "System Events" to display alert "已复制到剪贴板" message frontAppId buttons {""} default button "" giving up after 2
'
