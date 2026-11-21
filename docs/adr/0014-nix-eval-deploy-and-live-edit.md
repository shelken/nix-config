# Nix 求值、部署工具链与配置链接约定

日期: 2026-11-21

集中记录影响整仓 Nix 求值、构建、部署与 macOS 配置激活的核心取舍，取代散落在各文件头部的说明注释

## 规则

- macOS 主机 MUST 用 `nixpkgs-unstable`（`nixpkgs-darwin`）而非 `nixos-unstable`：该分支发布不等待 NixOS 测试套件，darwin 修复不会被无关的 NixOS 测试失败阻塞
- deploy-rs 激活器 MUST 取自 `nixpkgs` 自带的包（`lib/deployRsLib.nix` 保留上游 lib）：上游 lib 默认从源码现场编译 Rust，公共 binary cache 未命中会显著拖慢部署
- `mkConfigLink` MUST 接收 Nix 路径字面量（如 `./settings.toml`）：`config.shelken.dotfiles.liveEdit = true` 时软链 `~/nix-config/<相对路径>` 指向工作树，支持免 rebuild 热加载；为 `false`（默认及远程部署节点）时 MUST 拷进 Nix store 保证闭包自包含与原子回滚；求值期经 `builtins.pathExists` 校验输入树中该路径存在，拦截移动文件后未更新调用处
- Determinate Nix 下（`nix.enable = false`）nix-darwin 不接管 registry，MUST 手动维护 `/etc/nix/registry.json`（`modules/features/nix/nix-settings.nix` 直接写出），把 `nix run nixpkgs#...` 映射到本 flake 锁定的 `nixpkgs-darwin`，避免额外拉取另一份 nixpkgs 源码树
- Time Machine 排除 MUST 用 `tmutil addexclusion <路径>`（不带 `-p`）给目录打 sticky xattr（`modules/features/backup/time-machine.nix`），MUST NOT 写 `SkipPaths`：`-p` 无 root 报 exit 80，有 root 仍要求 Full Disk Access，激活终端没有该权限

## 考虑过的替代方案

- 全平台共用 `nixos-unstable`：少一个 flake input，但 darwin 更新经常被 NixOS 测试队列卡住数天
- Time Machine 用 `tmutil addexclusion -p`：标记不随目录重建丢失，但要求给终端授予 Full Disk Access
- 始终把配置文件拷进 store：逻辑单一，但高频调试编辑器与 AI 配置每次改动都要 rebuild

## 后果

- nix-darwin 与 NixOS 的 nixpkgs 锁点独立，跨平台公共包版本可能短暂不一致
- `liveEdit = true` 校验的是求值输入树，指向的是工作树路径；输入快照存在而工作树未同步迁移时仍可能悬空软链
- Determinate 的 `getRegistries()` 匹配系统 registry 前仍调 `getGlobalRegistry()`，全局 registry 缓存失效时仍可能访问远端，本配置解决的是锁定 nixpkgs 目标而非彻底屏蔽远端查询
- Time Machine 排除标记附着在目录 xattr 上，删除重建后丢失；仅当排除列表非空时注册激活节点，激活脚本对已存在路径按需补打
