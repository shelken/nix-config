#!/usr/bin/env bash
osascript -e '
  tell application "System Events" to set frontAppId to bundle identifier of first process whose frontmost is true
  set the clipboard to frontAppId
  tell application "System Events" to display alert "已复制到剪贴板" message frontAppId buttons {""} default button "" giving up after 2
'
