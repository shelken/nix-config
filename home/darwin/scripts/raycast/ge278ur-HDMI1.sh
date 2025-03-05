#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title 显示器 tv
# @raycast.mode compact

# Optional parameters:
# @raycast.icon 📺
# @raycast.packageName shelken
# @raycast.needsConfirmation false

# Documentation:
# @raycast.description 将显示器切换到HDMI1接口
# @raycast.author shelken
# @raycast.authorURL https://raycast.com/shelken

# echo "Hello World! Argument1 value: "$1""
# m1ddc display 1 set input 15
/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay set -name=GE278UR -vcp=inputSelect -ddc=18
