# nix-config

基于 Nix Flakes 的多平台配置仓库，管理 macOS (nix-darwin) 和 Linux (NixOS) 的系统与 Home Manager 配置

## 布局

- `modules/base`: 跨平台共享配置
- `modules/darwin`: macOS (nix-darwin) 特有配置
- `modules/nixos`: Linux (NixOS) 特有配置
- `home/`: Home Manager 配置，按平台 (`darwin`/`linux`) 划分
- `hosts/<hostname>/default.nix`: 机器配置
- `vars/`: 全局变量（用户名、邮箱等）
- `lib/`: 自定义函数（`mylib.scanPaths`, `mylib.relativeToRoot` 等）
- `_sources/`: nvfetcher 管理的非 nixpkgs 源
- `secrets/`: 引用外部 secrets flake，通过 sops-nix 做秘密管理
- `.host-profile`: 当前机器对应 flake 中定义的名字

## 基本约束

- 除非用户允许否则不使用 `just sw`(nix-darwin范围变更) / `just hm`(home-manager 范围变更)
- 更多常用命令在 `justfile`，用 `just` 查看可用快捷命令
- 日常编码、提交与验证规范见 `CODING_STANDARDS.md`

## 配置原则

引入/管理一个新软件的配置时按此顺序决策：

1. 优先 home-manager 现成模块；没有才自己写文件关联
2. 桌面端 GUI 产品遵循不编译原则，用nix-darwin/nixpkgs安装（brew cask 等）；安装包的方式必须与用户确认
3. home-manager 没有现成配置时，使用 `mylib.mkConfigFile / mylib.mkConfigLink`；开发机开启 `shelken.dotfiles.liveEdit` 即可即时生效，远程部署机自动使用纯 Nix Store 路径保证自包含与原子回滚
4. 本地已有配置时，告知用户, 让用户决定如何对待存在的配置
5. 如果软件会自动生成大量默认配置到配置文件的，优先"读取后合并覆盖"，默认不做全量声明式管理

## Tips

- 执行任何nix操作(eval/build)前确保自己新增或删除的文件被git跟踪

## Agent 文档

- 问题、规格与 Wayfinder 路线地图使用 GitHub Issues 管理，详见 `docs/agents/issue-tracker.md`
- 采用单一上下文：根目录 `GLOSSARY.md` 记录共享领域知识，架构决策记录放在 `docs/adr/`，详见 `docs/agents/domain.md`
- 创建、修改或测试机器特定定时任务时使用 `.agents/skills/create-task/`
