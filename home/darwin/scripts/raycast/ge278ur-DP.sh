#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title 显示器 sakamoto
# @raycast.mode compact

# Optional parameters:
# @raycast.icon https://api.iconify.design/heroicons/server-stack.svg
# @raycast.packageName shelken
# @raycast.needsConfirmation false

# Documentation:
# @raycast.description 将显示器切换到DP接口
# @raycast.author shelken
# @raycast.authorURL https://raycast.com/shelken

# echo "Hello World! Argument1 value: "$1""
# m1ddc display 1 set input 18
/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay set -name=GE278UR -vcp=inputSelect -ddc=17

