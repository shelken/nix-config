#!/usr/bin/env bash
osascript -e '
  if application "Finder" is not running then
    return "Not running"
  end if

  tell application "Finder"
    set pathList to (POSIX path of ((insertion location) as alias))
  end tell
  set command to "open -a kitty"
  do shell script command

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
