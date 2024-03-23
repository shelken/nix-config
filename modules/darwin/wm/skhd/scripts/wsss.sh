#!/bin/bash
yabai -m window --space $1 &> /dev/null
yabai -m query --spaces --space $1 | jq -r '.windows[0] // empty' | xargs yabai -m window --focus &> /dev/null
