down_gh_files() {
    # 检查 gh 命令是否存在
    if ! command -v gh >/dev/null 2>&1; then
        echo "Error: 'gh' command not found. Please install GitHub CLI first."
        return 1
    fi

    # 检查输入参数是否正确
    if [ $# -ne 2 ]; then
        echo "Usage: down_gh_files <username/repo> <file/path>"
        return 1
    fi

    # 获取用户输入的参数
    local repo=$1
    local filepath=$2
    local repo_name=$(basename "$repo")
    local temp_dir=$(mktemp -d)

    # Clone 仓库到临时目录，仅拉取最新的 commit
    echo "Cloning $repo..."
    gh repo clone "$repo" "$temp_dir" -- --depth=1 || {
        echo "Error: Failed to clone repository '$repo'."
        rm -rf "$temp_dir"
        return 1
    }

    # 检查目标文件或目录是否存在
    if [ ! -e "$temp_dir/$filepath" ]; then
        echo "Error: Path '$filepath' not found in repository '$repo'."
        rm -rf "$temp_dir"
        return 1
    fi

    # 移动目标文件或目录到当前工作目录
    echo "Extracting $filepath..."
    mv "$temp_dir/$filepath" . || {
        echo "Error: Failed to move '$filepath' to current directory."
        rm -rf "$temp_dir"
        return 1
    }

    # 清理临时目录
    rm -rf "$temp_dir"
    echo "Successfully downloaded '$filepath' from '$repo'."
}
