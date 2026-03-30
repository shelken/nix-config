if ! command -v gh >/dev/null 2>&1; then
    echo "Error: 'gh' not found."
    return 1
fi

if [ $# -ne 1 ]; then
    echo "Usage: down_gh_files <github-url>"
    echo "  文件: https://github.com/owner/repo/blob/branch/path/to/file"
    echo "  目录: https://github.com/owner/repo/tree/branch/path/to/dir"
    return 1
fi

local url=$1
# 解析 URL: github.com/{owner}/{repo}/{blob|tree}/{branch}/{path}
if [[ ! $url =~ github\.com/([^/]+)/([^/]+)/(blob|tree)/([^/]+)/(.+) ]]; then
    echo "Error: 无法解析 URL，请粘贴 GitHub 文件或目录页面的地址"
    return 1
fi

local owner=$match[1]
local repo=$match[2]
local type=$match[3] # blob=文件, tree=目录
local branch=$match[4]
local filepath=$match[5]

if [[ $type == "blob" ]]; then
    # 单文件：用 gh api 直接下载 raw 内容
    local filename=$(basename "$filepath")
    echo "下载文件 $filename ..."
    gh api "repos/$owner/$repo/contents/$filepath?ref=$branch" \
        --jq '.download_url' | xargs curl -fsSL -O
    echo "✅ $filename"
else
    # 目录：sparse clone 只拉取目标目录
    local temp_dir=$(mktemp -d)
    echo "下载目录 $filepath ..."
    git clone --depth=1 --filter=blob:none --sparse \
        "https://github.com/$owner/$repo.git" "$temp_dir" -b "$branch" -q
    git -C "$temp_dir" sparse-checkout set "$filepath"
    mv "$temp_dir/$filepath" .
    rm -rf "$temp_dir"
    echo "✅ $(basename $filepath)"
fi
