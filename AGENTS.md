# AGENTS.md

## 原则

- 中文对话，中文注释，中文文档

## 文档/skill

- 写 `README/AGENTS` 文档时，只记录长期规则、长期事实和硬约定；不要记录一次性问题、低频问题、强时效结论或流水账。
- 项目级 skill 必须放在项目根目录 `.agents/skills/` 下，不要放到 `home/` 等用户环境配置目录。

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

## 验证

- 执行`just bd`或者`just hm`等nix构建命令前, 确保新增或删除的文件加入了git, 只有add之后才会生效
- 修改配置后, 使用`nix eval` 和 `just bd`验证当前配置是否正确
