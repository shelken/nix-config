# AGENTS.md

## 原则

- 中文对话，中文注释，中文文档

## 文档/skill

- 写`README/AGENTS`文档的时候永远不把`一次性问题`进行记录, 也就是说, 不要把那些 不具备通用性/不可能重复犯/低频率/强时效性 的问题记录, 只有真正的 硬规则/长期事实/长期规则 才值得被记下

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
- `.env` 文件目前会存放当前机器对应flake中定义的名字

## 关键约定

- **软件源**: 使用 `nvfetcher` 管理非 nixpkgs 源
- **秘密管理**: 引用外部 `secrets` flake（通过 sops-nix）

## Git 提交规则

- commit 前先在 direnv 环境运行一次 pre-commit（例如：`direnv exec . pre-commit run -a`）
- 优先使用`Conventional Commits`格式提交git commit，标题 **英文**，内容 **中文**
