# Home

本目录使用 [Nix Home Manager](https://github.com/nix-community/home-manager)
来管理用户级别的配置（dotfiles、应用程序、软件包等）。通过将配置模块化，实现了跨多台机器（macOS 和 Linux）的复用和个性化。

## 目录结构

```
.
├── apps/
├── base/
├── darwin/
└── linux/
```

### `apps/`

存放各个独立的应用程序配置。每个子目录或 `.nix` 文件对应一个应用，例如 `neovim`, `kitty`, `zsh` 等。

这些配置是独立的，可以被不同的主机或系统环境（如 `darwin` 或
`linux`）按需导入，从而实现配置的灵活组合。

**例如:**

- `apps/neovim/`: Neovim 编辑器的相关配置。
- `apps/kitty/`: Kitty 终端的配置。
- `apps/zsh/`: Zsh shell 的配置，包括插件和主题。
- `apps/dev/`: 统一管理开发环境相关的工具和语言（Go, Rust, Java 等）。

### `base/`

存放所有系统（macOS 和 Linux）共享的基础配置。这是构建用户环境的基石。

- **`core/`**: 定义了最核心的软件包和配置，包括：
  - `core.nix`: 安装通用命令行工具，如 `eza`, `bat`, `zoxide`。
  - `git.nix`: 统一的 `git` 和 `lazygit` 配置。
  - `ssh.nix`: 基础的 `ssh` 客户端配置。
- **`desktop/`**: 包含桌面环境相关的通用配置（目前主要是 `hyprland` 的基础设置）。
- **`server/`**: 包含适用于服务器环境的通用配置，通常会安装一个更精简的工具集。
- **`home.nix`**: Home Manager 的入口配置，定义了用户名和状态版本等基本信息。

### `darwin/`

存放 macOS (Darwin) 系统特有的配置。

它会首先导入 `base/` 中的共享配置，并在此基础上添加 macOS 专属的设置，例如：

- `core.nix`: 安装 macOS 特有的包，如 `gh` (GitHub CLI), `rclone`。
- `shell.nix`: 为 `bash` 和 `zsh` 添加 Homebrew 相关的路径。
- `wm/`: 配置 macOS 的窗口管理器，如 `aerospace`。
- `apps/`: 导入并启用 macOS 上使用的特定应用，如 `raycast`, `karabiner`, `squirrel`
  (鼠须管输入法) 等。
- `scripts/`: 存放 macOS 特有的脚本，例如用于 Raycast 的快捷指令。

### `linux/`

存放 Linux 系统特有的配置。

它同样会导入 `base/` 中的共享配置，并添加 Linux 专属的设置。目前主要面向服务器环境，例如：

- `core.nix`: 导入基础配置。
- `default.nix`: 导入适用于服务器的 `base/server` 配置，并启用 `vscode-server` 等服务。
