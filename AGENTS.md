# 项目记忆 (Project Context)

### 架构概览

这是一个基于 Nix Flakes 的多平台配置仓库，管理 macOS (nix-darwin) 和 Linux (NixOS)。

- **入口**: `flake.nix`
- **模块化**:
  - `modules/darwin`: macOS 特有配置。
  - `modules/nixos`: Linux 特有配置。
  - `home/`: Home Manager 配置，按平台 (`darwin`/`linux`) 划分。
- **机器配置**: `hosts/` 目录下存放各主机的具体配置（如 `yuuko`, `sakamoto`, `mio` 等）。
- **变量与库**:
  - `vars/`: 定义全局变量（用户名、邮箱等）。
  - `lib/`: 自定义 Nix 函数库。

### 关键工具与工作流

- **任务管理**: 使用 `justfile`。常用命令：
  - `just sw` 或 `just switch`: 应用当前配置。
  - `just b`: 仅构建不应用。
  - `just deploy <host> <target>`: 使用 Colmena 部署远程主机。
- **软件源**: 使用 `nvfetcher` 管理非 nixpkgs 源。
- **秘密管理**: 引用外部 `secrets` flake。

### 常用路径参考

- Darwin 软件配置: `modules/darwin/apps/`
- Home Manager 核心: `home/darwin/core.nix` 或 `home/linux/core.nix`
- 机器特定配置: `hosts/<hostname>/default.nix`
