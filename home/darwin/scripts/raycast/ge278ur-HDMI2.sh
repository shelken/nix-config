#!/usr/bin/env bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title 显示器 mio
# @raycast.mode compact

# Optional parameters:
# @raycast.icon 💻
# @raycast.packageName space.ooooo
# @raycast.needsConfirmation false

# Documentation:
# @raycast.description 将显示器切换到 HDMI2 接口
# @raycast.author shelken
# @raycast.authorURL https://raycast.com/shelken

# echo "Hello World! Argument1 value: "$1""
# m1ddc display 1 set input 17
/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay set -name=GE278UR -vcp=inputSelect -ddc=15

