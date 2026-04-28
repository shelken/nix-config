# AGENTS.md

## 原则

- 中文对话，中文注释，中文文档

## 架构

这是一个基于 Nix Flakes 的多平台配置仓库，管理 macOS (nix-darwin) 和 Linux (NixOS)。

- **入口**: `flake.nix`
- **模块化**:
  - `modules/base`: 跨平台共享配置
  - `modules/darwin`: macOS 特有配置
  - `modules/nixos`: Linux 特有配置
  - `home/`: Home Manager 配置，按平台 (`darwin`/`linux`) 划分
- **机器配置**: `hosts/<hostname>/default.nix`
- **变量与库**:
  - `vars/`: 全局变量（用户名、邮箱等）
  - `lib/`: 自定义函数（`mylib.scanPaths`, `mylib.relativeToRoot` 等）

## 关键约定

- **软件源**: 使用 `nvfetcher` 管理非 nixpkgs 源
- **秘密管理**: 引用外部 `secrets` flake（通过 sops-nix）

## Git 提交规则

- commit 前先在 direnv 环境运行一次 pre-commit（例如：`direnv exec . pre-commit run -a`）
- 优先使用`Conventional Commits`格式提交git commit，标题 **英文**，内容 **中文**
