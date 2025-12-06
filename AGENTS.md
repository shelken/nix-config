# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this
repository.

## 项目概述

这是一个个人 Nix 配置仓库，用于管理多个 macOS（通过 nix-darwin）和 Linux（NixOS）系统的配置。采用 Flakes 架构，支持 8+ 台不同主机。

## 常用命令

所有命令通过 `justfile` 管理。当前使用的 profile 在 `.env` 文件中定义：`PROFILE=<主机名>`。

### 构建和应用配置

- `just switch` 或 `just sw` - 应用当前配置到本地机器
- `just rebuild` 或 `just b` - 构建系统但不应用
- `just rebuild-debug` 或 `just bd` - 调试模式构建

### 代码质量和维护

- `just fmt` - 格式化代码（deadnix + nix fmt）
- `just up` - 更新所有 flake 输入
- `just upp <输入名>` - 更新指定 flake 输入
- `just gc` - 清理无用包（默认最近 0 小时）
- `just gc-all` - 清理所有无用包

### 部署

- `just deploy <主机> <目标机器>` - 远程部署配置
  - Linux：使用 `nixos-rebuild switch` 远程部署
  - macOS：使用 `colmena apply` 基于标签部署
- `just nixos-anywhere <主机> <目标机器>` - 使用 nixos-anywhere 部署到裸机

### 开发和测试

- `just search <包名>` - 在 nixos-unstable 中搜索包
- `just prefetch-gh <所有者>/<仓库>` - 生成带哈希的 fetchFromGitHub 表达式
- `just gen-image <主机> <格式>` - 生成系统镜像（ISO、QCOW2 等）
- `just ls-gen`（仅 macOS）- 显示配置生成历史

### 配置测试

- `just aerospace-test` - 测试 aerospace 窗口管理器配置
- `just continue-test` - 测试 Continue.dev 配置
- `just wez-test` - 测试 WezTerm 配置

## 高级架构

### Flake 架构模式

配置采用模块化设计，每个主机配置组合：

1. **平台模块**：`modules/darwin/`（macOS）或 `modules/nixos/`（Linux）
2. **主机特定模块**：`hosts/<主机名>/`
3. **Home Manager 模块**：`home/darwin/` 或 `home/linux/` + `hosts/<主机名>/home.nix`
4. **秘密配置**：`secrets/home.nix`（通过外部 GitHub 仓库管理）

### 自定义库系统（`lib/`）

- `mylib.scanPaths` - 自动扫描目录中所有 `.nix` 文件并导入
- `mylib.nixosSystem` / `mylib.macosSystem` - 自定义系统构建函数，传递特殊参数
- `mylib.relativeToRoot` - 创建相对于仓库根目录的路径
- `mylib.mkBoolOpt` - 创建布尔选项的辅助函数
- `mylib.calcUniformSchedule` - 为主机计算均匀分布的计划时间

### 变量集中管理

- 用户信息、网络配置等全局变量存储在 `vars/` 目录
- 通过 `myvars` 在所有配置中共享
- 网络配置分离：`vars/networking.nix`（全局） + `hosts/<主机名>/networking.nix`（主机特定）

### 秘密管理

- 使用外部 GitHub 仓库 `shelken/secrets.nix` 管理敏感信息
- 作为 flake 输入引入：`secrets.url = "github:shelken/secrets.nix"`
- 需要在 `~/.config/nix/nix.conf` 或 `/etc/nix/nix.custom.conf` 中配置 GitHub 访问令牌

### 平台差异处理

- **macOS**：使用 nix-darwin，通过 `darwin-rebuild` 管理
- **Linux**：使用 NixOS，通过 `nixos-rebuild` 管理
- `justfile` 通过条件语句自动检测平台并执行相应命令

### 配置生成模式

在 `flake.nix` 中，每个主机配置采用以下模式：

```nix
sakamotoModules = {
  darwin-modules = map mylib.relativeToRoot [
    "modules/darwin"          # 平台通用模块
    "hosts/sakamoto"          # 主机特定配置
  ];
  home-modules = map mylib.relativeToRoot [
    "home/darwin"             # 平台用户配置
    "secrets/home.nix"        # 秘密配置
    "hosts/sakamoto/home.nix" # 主机用户配置
  ];
};
```

### 开发工具集成

- 预提交钩子配置在 `.pre-commit-config.yaml`
- 代码格式化：deadnix + nix fmt
- 拼写检查：typos
- 非 Nix 文件格式化：prettier

## 重要注意事项

1. **环境设置**：必须在 `.env` 文件中设置 `PROFILE=<主机名>`，命令依赖此变量
2. **秘密访问**：需要 GitHub 访问令牌才能获取 secrets.nix 仓库
3. **平台特定**：某些命令仅适用于特定平台（通过 `[linux]` 或 `[macos]` 标记）
4. **部署差异**：Linux 和 macOS 使用不同的部署工具和策略
