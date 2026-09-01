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
- commit 前先add然后运行一次 pre-commit
- 优先使用 Conventional Commits 格式提交，标题 **英文**，内容 **中文**
- 修改配置后，使用 `just bd`(nix-darwin范围验证) / `just hm-build`(home-manager 范围验证) 等命令进行验证
- 使用 `just sw`(nix-darwin范围变更) / `just hm`(home-manager 范围变更) 前; 确保新增或删除的文件已 `git add`，否则不生效;
- 一般使用 `nh search` 搜索 nixpkgs 中的包
- 项目级 skill 必须放在项目根目录 `.agents/skills/` 下，不要放到 `home/` 等用户环境配置目录
- 更多常用命令在 `justfile`，用 `just` 查看可用快捷命令
- 禁止 nix run / nix shell 命令; 在devshell引入缺失工具

## 软件源与秘密

- 使用 `nvfetcher` 管理非 nixpkgs 源
- 引用外部 `secrets` flake 做秘密管理（通过 sops-nix）

## Agent skills

### 问题跟踪器

问题、规格与 Wayfinder 路线地图使用 GitHub Issues 管理。详见 `docs/agents/issue-tracker.md`。

### 领域文档

采用单一上下文：根目录 `CONTEXT.md` 记录共享领域知识，架构决策记录放在 `docs/adr/`。详见 `docs/agents/domain.md`。

### 声明式定时任务

创建、修改或测试机器特定定时任务时使用 `.agents/skills/create-task/`。
