#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title 写出剪贴板内容
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 🤖

# Documentation:
# @raycast.description 与粘贴不同，使用osascript将剪贴板内容像用户输入一样进行自动输入
# @raycast.author shelken

# 将剪贴板中的内容粘贴到当前焦点窗口
pbpaste | osascript -e 'tell application "System Events" to keystroke (the clipboard)'

