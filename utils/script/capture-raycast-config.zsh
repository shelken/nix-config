#!/usr/bin/env zsh

# file location: <anywhere; but advisable in the PATH>

# This script will export/import the raycast configs to/from the location specified in the target directory.
# Reference for keystrokes/keycodes: https://eastmanreference.com/complete-list-of-applescript-key-codes

# source code: https://github.com/vraravam/dotfiles/blob/master/scripts/capture-raycast-configs.sh

# type red &> /dev/null 2>&1 || source "${HOME}/.shellrc"
red() {
  echo -e "\033[31m$*\033[0m"
}

green() {
  echo -e "\033[32m$*\033[0m"
}

yellow() {
  echo -e "\033[33m$*\033[0m"
}

usage() {
  echo "$(red "Usage"): $(yellow "${1} <e/i> <target-dir-location>")"
  echo "  $(yellow 'e')                   --> Export from system"
  echo "  $(yellow 'i')                   --> Import into system"
  echo "  $(yellow 'target-dir-location') --> Directory name where the config has to be exported to/imported from"
  exit 1
}

is_non_zero_string() {
  [[ -n "$1" ]]
}

is_file() {
  [[ -f "$1" ]]
}

error() {
  red "Error: $1"
  exit 1
}

success() {
  green "Success: $1"
}

[ $# -ne 2 ] && usage "${0}"

[[ "${1}" != 'e' && "${1}" != 'i' ]] && echo "$(red 'Unknown value entered') for first argument: '${1}'" && usage "${0}"

local target_dir="${2}"
target_dir="$(cd "${target_dir}" 2>/dev/null && pwd || echo "${target_dir}")"
local target_file="${target_dir}/latest.rayconfig"
# ensure_dir_exists "${target_dir}"

! is_non_zero_string "${RAYCAST_SETTINGS_PASSWORD}" && error "Cannot proceed without the 'RAYCAST_SETTINGS_PASSWORD' env var set; Aborting!!!"

if [[ "${1}" == 'e' ]]; then
  is_file "${target_dir}/latest.rayconfig" && rm -rf "${target_dir}/Raycast.rayconfig"

  open raycast://extensions/raycast/raycast/export-settings-data

  osascript <<EOF
    tell application "System Events"
      key code 36
      delay 0.3

      if (static text "Enter password" of window 1 of application process "Raycast") exists then
        keystroke "${RAYCAST_SETTINGS_PASSWORD}"
        delay 0.3

        key code 36
        delay 0.3

        keystroke "${RAYCAST_SETTINGS_PASSWORD}"
        delay 0.3

        key code 36
        delay 0.3
      end if

      key code 5 using {command down, shift down}
      delay 0.3

      keystroke "${target_dir}"
      delay 0.3

      key code 36
      delay 0.7

      key code 36
      delay 0.5

      key code 53
      key code 53
      delay 0.5 # 导出时间
    end tell
EOF

  mv "${target_dir}"/Raycast*.rayconfig "${target_file}"
  success "Successfully exported raycast configs to: $(yellow "${target_file}")"
elif [[ "${1}" == 'i' ]]; then
  ! is_file "${target_file}" && error "Couldn't find file: '$(yellow "${target_file}")' for import operation; Aborting!!!"
  
  # 解密
  TEMP_DIR=$(mktemp -d)
  trap "rm -rf \"$TEMP_DIR\"; echo \"临时目录已删除: $TEMP_DIR\"" EXIT ERR
  OUTPUT_FILE="$TEMP_DIR/$(basename "$target_file" .rayconfig).gz"}
  openssl enc -d -aes-256-cbc -nosalt -in "$target_file" -k "$RAYCAST_SETTINGS_PASSWORD" 2>/dev/null | tail -c +17 > "$OUTPUT_FILE"

  open raycast://extensions/raycast/raycast/import-settings-data

  osascript <<EOF
    tell application "System Events"
      key code 36
      delay 0.3

      key code 5 using {command down, shift down}
      delay 0.3

      keystroke "$OUTPUT_FILE"
      delay 0.5

      key code 36 # 输入地址后回车
      delay 1

      key code 36 # 
      delay 1

      key code 36 # 提示框确认
      delay 5

      key code 36 
      delay 0.5

      key code 53
      key code 53
    end tell
EOF

  success "Successfully imported raycast configs from: $(yellow "${target_file}")"
fi

unset target_dir
unset target_file
