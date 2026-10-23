#!/usr/bin/env bash

usage() {
  cat <<'EOF'
用法: new-kitty

打开新的 Kitty 窗口。
EOF
}

if [[ $# -eq 1 && ( "$1" == "-h" || "$1" == "--help" ) ]]; then
  usage
  exit 0
fi

if [[ $# -ne 0 ]]; then
  usage >&2
  exit 64
fi

exec /usr/bin/open -na kitty
