**注意：本文档使用中文编写。**

# 记忆

- 对话默认使用中文

# 项目概述

本仓库是一个用于管理系统配置（NixOS 和 darwin/macOS）及用户环境（home-manager）的 Nix
flake。它旨在为多台机器创建可复现的、声明式的配置。

## 关键组件

### Flake 核心文件

- `flake.nix`: Flake 的入口文件。它定义了项目的输入（如
  `nixpkgs`）和输出，包括 NixOS 配置、macOS 配置和 home-manager 配置。
- `flake.lock`: 锁定所有输入的精确版本，确保可复现性。

### 主机与用户配置

- `hosts/`: 包含特定于主机的配置。每个子目录（例如
  `ling`、`mio`）对应一台不同的主机，并通过导入模块来定义其独特的系统设置。
- `home/`: 使用 `home-manager` 管理用户级别的配置。
  - `home/apps/`: 包含各个应用的配置（例如 `neovim`、`kitty`、`zsh`）。
  - `home/base/`: 定义跨系统共享的基础 home-manager 配置。
  - `home/darwin/` & `home/linux/`: 平台特定的 home-manager 配置。

### 可复用模块与逻辑

- `modules/`: 一系列可复用的 NixOS 和 darwin 模块，用于封装特定功能（例如
  `desktop`、`nvidia`、`secrets`）。这有助于提高模块化程度和代码复用率。
- `lib/`: 包含在整个 flake 中用于构建系统配置的辅助函数和库代码。
- `overlays/`: 用于自定义现有的 Nix 软件包或引入新包。
- `vars/`: 存储在不同配置间共享的变量（例如网络设置）。

### 秘密管理

- `secrets/`: 用于管理敏感信息，很可能使用了 `agenix` 或 `sops-nix` 之类的工具。

### 包源管理

- `_sources/` & `nvfetcher.toml`: 使用 `nvfetcher` 管理和锁定非 Nixpkgs 软件包的版本。

### 工具与自动化

- `justfile`: 定义了一系列用于管理 flake 的命令和任务，例如构建配置、应用更改和运行更新。
- `.github/workflows/`: 包含用于自动化的 GitHub Actions 工作流，例如与上游仓库同步。
- `utils/`: 包含各种实用工具脚本。

## 工作原理

1.  **主机 (Hosts)**: 每台机器在 `hosts` 目录下都有一个专门的配置。
2.  **模块 (Modules)**: 主机配置从 `modules` 目录导入模块，以启用和配置系统服务与功能。
3.  **Home-Manager**: 用户特定的设置、dotfiles 和软件包通过 `home-manager` 进行管理，其配置在 `home`
    目录中定义。
4.  **构建 (Building)**: 使用 `nixos-rebuild` (NixOS) 或 `darwin-rebuild`
    (macOS) 命令将此 flake 中定义的配置应用到目标系统。`justfile` 很可能为这些命令提供了方便的别名。

这种结构使得对复杂系统和用户环境的管理变得高度组织化、声明式且可复现。
