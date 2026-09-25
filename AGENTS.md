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
- 修改配置后，只有本机情况(检查.env对应的PROFILE), 才使用 `just bd`(nix-darwin范围验证) / `just hm-build`(home-manager 范围验证) 等命令进行验证; 其他机器的情况仅使用轻量化的命令进行校验
- 除非用户允许否则不使用 `just sw`(nix-darwin范围变更) / `just hm`(home-manager 范围变更)
- 一般使用 `nh search` 搜索 nixpkgs 中的包
- 项目级 skill 必须放在项目根目录 `.agents/skills/` 下，不要放到 `home/` 等用户环境配置目录
- 更多常用命令在 `justfile`，用 `just` 查看可用快捷命令

## 软件源与秘密

- 使用 `nvfetcher` 管理非 nixpkgs 源
- 引用外部 `secrets` flake 做秘密管理（通过 sops-nix）

## 配置原则

引入/管理一个新软件的配置时按此顺序决策：

1. 优先 home-manager 现成模块；没有才自己写文件关联
2. 桌面端 GUI 产品遵循不编译原则，用nix-darwin/nixpkgs安装（brew cask 等）；安装包的方式必须与用户确认
3. home-manager 没有现成配置时，用 `mkOutOfStoreSymlink` 软链，保证仓库内编辑立即生效
4. 本地已有配置时，告知用户, 让用户决定如何对待存在的配置
5. 如果软件会自动生成大量默认配置到配置文件的，优先"读取后合并覆盖"，默认不做全量声明式管理

## Tips

- 执行任何nix操作(eval/build)前确保自己新增或删除的文件被git跟踪

## Agent skills

### 问题跟踪器

问题、规格与 Wayfinder 路线地图使用 GitHub Issues 管理。详见 `docs/agents/issue-tracker.md`。

### 领域文档

采用单一上下文：根目录 `CONTEXT.md` 记录共享领域知识，架构决策记录放在 `docs/adr/`。详见 `docs/agents/domain.md`。

### 声明式定时任务

创建、修改或测试机器特定定时任务时使用 `.agents/skills/create-task/`。
