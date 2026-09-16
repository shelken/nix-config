# Darwin system build

Darwin system build 让用户通过 `just bd` 构建当前机器的完整 system toplevel，查看系统与 Home 的组合差异，但不切换当前 generation

## Sub-features

- `darwin-build-doctor` 确认当前 host 与 Home 同源不变量
- `darwin-build-command` 运行仓库公开的 `just bd` 入口
- `darwin-build-toplevel` 构建 `darwinConfigurations.<host>.config.system.build.toplevel`
- `darwin-build-no-switch` 确认 system 与 Home profile 链接前后不变

## How to get to it (user POV)

- 在仓库根目录运行 `just bd`
- 需要保存标准 proof 时运行 `.agents/skills/verify-nix-config/scripts/verify.sh darwin-build`

## Driving it with Bash

Preconditions:

- `verify.sh doctor` 输出 `doctor=ok`
- 当前机器是 Darwin，且能读取对应 flake host
- evidence 目录不与其他 drive 共用

- **运行真实入口。** 执行 `.agents/skills/verify-nix-config/scripts/verify.sh darwin-build`。`transcript.log` 中的 nh pipeline 构建 `darwinConfigurations.<host>.config.system.build.toplevel`，命令退出码为 `0`
- **检查差异。** 读取 transcript 中的 `ADDED`、`REMOVED`、`CHANGED`。每项都能归因于当前工作树，无法归因的差异阻断 switch
- **确认无切换。** 读取 `summary.json`，`shared_profile_links_unchanged` 为 `true`
- **保留 proof。** 保存 helper 输出的 evidence 目录，至少包含 transcript、working tree 状态和链接快照

## Gotchas

- `just bd` 会构建系统 derivation，但不会更新 `/run/current-system`
- 完整系统 diff 会包含 Home、Homebrew、launchd 与其他未提交改动，不能只检查目标包名
- `nano` 等不同架构 host 可能受当前 nixpkgs 支持范围限制，不能把本机 build 成功外推到其他 host
- 构建成功不授权 `just sw`
