#!/usr/bin/env bash

usage() {
  cat <<'EOF'
Usage: gh-fetch <github-url>

按 GitHub 文件或目录页面地址直接下载内容到当前目录。
  文件: https://github.com/owner/repo/blob/branch/path/to/file
  目录: https://github.com/owner/repo/tree/branch/path/to/dir

Options:
  -h, --help  显示帮助信息
EOF
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
  usage
  exit 0
fi

if (( $# != 1 )); then
  usage >&2
  exit 1
fi

url=$1
pattern='github\.com/([^/]+)/([^/]+)/(blob|tree)/([^/]+)/(.+)'
if [[ ! $url =~ $pattern ]]; then
  echo "Error: 无法解析 URL，请粘贴 GitHub 文件或目录页面的地址" >&2
  exit 1
fi

owner=${BASH_REMATCH[1]}
repo=${BASH_REMATCH[2]}
kind=${BASH_REMATCH[3]}
branch=${BASH_REMATCH[4]}
filepath=${BASH_REMATCH[5]}

if [[ $kind == "blob" ]]; then
  filename=$(basename "$filepath")
  echo "下载文件 $filename ..."
  download_url=$(gh api "repos/$owner/$repo/contents/$filepath?ref=$branch" --jq '.download_url')
  curl -fsSL -O "$download_url"
  echo "✅ $filename"
else
  temp_dir=$(mktemp -d)
  trap 'rm -rf "$temp_dir"' EXIT
  echo "下载目录 $filepath ..."
  git clone --depth=1 --filter=blob:none --sparse \
    "https://github.com/$owner/$repo.git" "$temp_dir" -b "$branch" -q
  git -C "$temp_dir" sparse-checkout set "$filepath"
  mv "$temp_dir/$filepath" .
  echo "✅ $(basename "$filepath")"
fi
