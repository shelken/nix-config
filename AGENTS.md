# AGENTS.md

基于 Nix Flakes 的多平台配置仓库，管理 macOS (nix-darwin) 和 Linux (NixOS) 的系统与 Home Manager 配置。

## 目录结构

- `flake.nix`: Flake 入口
- `modules/base`: 跨平台共享配置
- `modules/darwin`: macOS (nix-darwin) 特有配置
- `modules/nixos`: Linux (NixOS) 特有配置
- `home/`: Home Manager 配置，按平台 (`darwin`/`linux`) 划分
- `hosts/<hostname>/default.nix`: 机器配置
- `vars/`: 全局变量（用户名、邮箱等）
- `lib/`: 自定义函数（`mylib.scanPaths`, `mylib.relativeToRoot` 等）
- `overlays/`: nixpkgs overlays
- `_sources/`: nvfetcher 生成的非 nixpkgs 源
- `secrets/`: 外部 secrets flake（通过 sops-nix）
- `.env`: 当前机器对应 flake 中定义的名字

## 基本约束

- 中文注释，中文文档
- commit 前先在 direnv 环境运行一次 pre-commit（`direnv exec . pre-commit run -a`）
- 优先使用 Conventional Commits 格式提交，标题 **英文**，内容 **中文**
- 执行 `just bd` / `just hm` 等构建命令前，确保新增或删除的文件已 `git add`，否则不生效
- 修改配置后，用 `nix eval` 和 `just bd` 验证当前配置是否正确
- 一般使用 `nh search` 搜索 nixpkgs 中的包
- 常用命令在 `justfile`，用 `just` 查看可用快捷命令
- 项目级 skill 必须放在项目根目录 `.agents/skills/` 下，不要放到 `home/` 等用户环境配置目录

## 软件源与秘密

- 使用 `nvfetcher` 管理非 nixpkgs 源
- 引用外部 `secrets` flake 做秘密管理（通过 sops-nix）

## Agent skills

### 问题跟踪器

问题、规格与 Wayfinder 路线地图使用 GitHub Issues 管理。详见 `docs/agents/issue-tracker.md`。

### 领域文档

采用单一上下文：根目录 `CONTEXT.md` 记录共享领域知识，架构决策记录放在 `docs/adr/`。详见 `docs/agents/domain.md`。
