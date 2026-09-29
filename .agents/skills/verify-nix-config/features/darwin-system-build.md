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

- helper 内置 doctor；门禁失败时不执行构建
- 当前机器是 Darwin，且能读取对应 flake host
- evidence 目录不与其他 drive 共用

- **运行真实入口。** 执行 `.agents/skills/verify-nix-config/scripts/verify.sh darwin-build`。`transcript.log` 中的 nh pipeline 构建 `darwinConfigurations.<host>.config.system.build.toplevel`，命令退出码为 `0`
- **检查差异。** 查看 transcript 中的新旧 store 路径及差异。若仅有 `PATHS`、`SIZE`、`DIFF` 汇总，继续比较新旧闭包与受影响的激活脚本；汇总不能证明具体配置变化。无法归因的差异阻断 switch
- **确认无切换。** 读取 `summary.json`，`shared_profile_links_unchanged` 为 `true`
- **保留 proof。** 保存 helper 输出的 evidence 目录，至少包含 transcript、working tree 状态和链接快照

## Gotchas

- `just bd` 会构建系统 derivation，但不会更新 `/run/current-system`
- 闭包差异不展示 Homebrew 声明和 activation 脚本的全部内容；系统切换前还需检查相关配置变化
- 其他主机按仓库规则轻量求值，本机 build 成功不能证明其他架构可构建
- 构建成功不授权 `just sw`
