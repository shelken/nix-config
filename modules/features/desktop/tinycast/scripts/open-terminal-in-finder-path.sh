#!/usr/bin/env bash

usage() {
  cat <<'EOF'
用法: open-terminal-in-finder-path

在 Kitty 新标签页里 cd 到 Finder 当前窗口的目录；路径同时留在剪贴板。
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
  if application "Finder" is not running then
    return "Not running"
  end if

  tell application "Finder"
    set pathList to (POSIX path of ((insertion location) as alias))
  end tell
  do shell script "/usr/bin/open -a kitty"

  set the clipboard to pathList

  tell application "System Events"
    # new tab
    keystroke "t" using {command down}
    # cd "thePath" return;
    keystroke "cd \""
    keystroke "v" using {command down}
    keystroke "\""
    keystroke return
    # clean screen
    keystroke "l" using {control down}
  end tell
'
