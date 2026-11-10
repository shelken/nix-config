# macOS 专用的低频任务；调用 just mac::<配方>

# 模块配方默认在本文件所在目录执行，这里统一回到仓库根目录，相对路径才与根 justfile 一致
set working-directory := '..'

# 列出不在 nix 管理内的 brew 包（只列出，不删除）
brew-diff:
    @brew bundle cleanup --file=$(nix path-info /run/current-system --recursive 2>/dev/null | grep Brewfile | head -1)
