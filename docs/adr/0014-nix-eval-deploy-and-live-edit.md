# Nix 求值、部署工具链与配置链接约定

日期: 2026-11-21

集中记录影响整仓 Nix 求值、构建、部署与 macOS 配置激活的核心取舍，取代散落在各文件头部的说明注释。

## 规则

- **`nixpkgs-darwin` 跟踪 `nixpkgs-unstable`**：macOS 主机使用 `nixpkgs-unstable` 而非 `nixos-unstable`。该分支发布不等待 NixOS 测试套件，darwin 修复不会被无关的 NixOS 测试失败阻塞。
- **`deploy-rs` 激活器取自 `nixpkgs`**：`lib/deployRsLib.nix` 保留上游 `deploy-rs` 的 `lib`，但把激活器替换为 `nixpkgs` 自带的 `deploy-rs` 包（#184）。上游 `lib` 默认从源码现场编译 Rust，公共 binary cache 未命中会显著拖慢部署。
- **`mkConfigLink` 按 `liveEdit` 切换来源**：`lib/default.nix` 的 `mkConfigLink` 接收 Nix 路径字面量（如 `./settings.toml`）。`config.shelken.dotfiles.liveEdit = true` 时用 `mkOutOfStoreSymlink` 拼出 `~/nix-config/<相对路径>` 指向工作树，支持免 rebuild 热加载；为 `false`（默认及远程部署节点）时拷进 Nix store，保证闭包自包含与原子回滚。传入路径字面量会在求值期经 `builtins.pathExists` 校验 flake 输入快照中该路径存在，拦截移动文件后未更新调用处的问题。
- **Determinate 下手动维护 `/etc/nix/registry.json`**：macOS 主机启用 Determinate Nix（`nix.enable = false`）时 nix-darwin 不接管 registry，`nix-settings.nix` 直接写出 `/etc/nix/registry.json`，将 `nix run nixpkgs#...` 映射到本 flake 锁定的 `nixpkgs-darwin`，避免额外拉取另一份 nixpkgs 源码树。
- **Time Machine 排除采用 sticky xattr**：`modules/features/backup/time-machine.nix` 使用 `tmutil addexclusion <路径>`（不带 `-p`）给目录打 `com.apple.metadata:com_apple_backup_excludeItem` 扩展属性，而不写入 `/Library/Preferences/com.apple.TimeMachine.plist`（`SkipPaths`）。`-p` 无 root 会报 exit 80，有 root 仍要求 Full Disk Access；激活脚本从无该权限的终端运行（`just sw`），只有不带 `-p` 的普通用户路径可行。

## 考虑过的替代方案

- **全平台共用 `nixos-unstable`**：少一个 flake input，但 darwin 更新经常被 NixOS 测试队列卡住数天。
- **Time Machine 使用 `tmutil addexclusion -p`**：标记不随目录重建丢失，但要求给终端授予 Full Disk Access，违反最小权限原则。
- **始终把配置文件拷进 Nix store**：逻辑更单一，但高频调试编辑器与 AI 配置时每次改动都要 rebuild。

## 后果

- `nix-darwin` 与 `NixOS` 的 `nixpkgs` 锁点独立，跨平台公共包版本可能短暂不一致。
- `mkConfigLink` 校验的是求值输入树，`liveEdit = true` 时指向的是工作树路径 `~/nix-config/<相对路径>`；若输入快照存在而工作树目录未同步迁移，仍可能产生悬空软链。
- Determinate Nix 的 `getRegistries()` 在匹配系统 registry 前仍会调用 `getGlobalRegistry()`，全局 registry 缓存失效时仍可能尝试访问远端，本配置解决的是锁定 `nixpkgs` 目标而非彻底屏蔽远端查询。
- Time Machine 的排除标记附着在目录 xattr 上，目录被删除重建后会丢失；因此仅当排除列表非空时注册激活节点，且激活脚本仅对已存在的路径执行 `xattr -p` 检查并按需补打。
