#!/run/current-system/sw/bin/zsh

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Yazi
# @raycast.mode silent

# Optional parameters:
# @raycast.icon https://yazi-rs.github.io/img/logo.png

# Documentation:
# @raycast.description open yazi in kitty
# @raycast.author shelken

/Applications/kitty.app/Contents/MacOS/kitty \
  --single-instance \
  -o macos_quit_when_last_window_closed=yes \
  -d ~/Code
#   -- \
#   /run/current-system/sw/bin/zsh -i -c 'yazi'


