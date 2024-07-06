#!/bin/bash
# 聚焦窗口后切换space
#yabai -m window --space $1 &> /dev/null
window1=$(yabai -m query --spaces --space $1 | jq -r '.windows[0] // empty') 
#yabai -m window --focus $window1 &> /dev/null
if [[ -z "$window1" ]]; then
  osascript -e 'display notification "空间 '"$1"' 没有窗口" with title "Yabai命令"'
  #osascript -e 'display notification "空间没有窗口" with title "Yabai命令"'
  #echo "空间$1没有窗口"
else
  yabai -m window --focus $window1 &> /dev/null
fi
