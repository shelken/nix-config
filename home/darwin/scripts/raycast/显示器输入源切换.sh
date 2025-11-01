#!/usr/bin/env bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title 显示器输入源切换
# @raycast.mode compact

# Optional parameters:
# @raycast.icon 🖥️
# @raycast.argument1 { "type": "dropdown", "placeholder": "选择接口", "data": [{"title": "DP(sakamoto)", "value": "17"}, {"title": "HDMI1(tv)", "value": "18"}, {"title": "HDMI2(mio)", "value": "15"}] }

# memo: redmi: {"7": "DP", "18": "HDMI1", "15": "HDMI2", "8": "typec"}

# Documentation:
# @raycast.description 将显示器切换到 特定 接口（该命令依赖 BetterDisplay）
# @raycast.author shelken
# @raycast.authorURL https://raycast.com/shelken

inputSource=$1
/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay set -name=GE278UR -vcp=inputSelect -ddc=$inputSource
