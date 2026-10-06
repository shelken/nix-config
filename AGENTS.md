# nix-config

基于 Nix Flakes 的多平台配置仓库，管理 macOS (nix-darwin) 和 Linux (NixOS) 的系统与 Home Manager 配置

## 布局

- `modules/{base,darwin,nixos}`: 跨平台共享、macOS、Linux 配置
- `home/`: Home Manager 配置，按平台 (`darwin`/`linux`) 划分
- `hosts/<hostname>/default.nix`: 机器配置
- `vars/`: 全局变量（用户名、邮箱等）
- `lib/`: 自定义函数（`mylib.scanPaths`、`mylib.relativeToRoot` 等）
- `_sources/`: nvfetcher 管理的非 nixpkgs 源
- `secrets/`: 引用外部 secrets flake，通过 sops-nix 做秘密管理
- `.host-profile`: 当前机器对应 flake 中定义的名字

## 基本约束

- 未经用户允许，不使用 `just sw`（nix-darwin 范围变更）与 `just hm`（home-manager 范围变更）
- 安装包的方式必须与用户确认
- 执行任何 nix 操作（eval/build）前，确保自己新增或删除的文件已被 git 跟踪
- 新增或调整软件配置前，先读 `docs/agents/software-config.md`
- 日常编码、提交与验证规范见 `CODING_STANDARDS.md`

## Agent 文档

- 问题、规格与 Wayfinder 路线地图使用 GitHub Issues 管理，详见 `docs/agents/issue-tracker.md`
- 采用单一上下文：根目录 `GLOSSARY.md` 记录共享领域知识，架构决策记录放在 `docs/adr/`，详见 `docs/agents/domain.md`
- 创建、修改或测试机器特定定时任务时使用 `.agents/skills/create-task/`
