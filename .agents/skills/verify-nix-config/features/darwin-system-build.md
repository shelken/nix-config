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

- **运行真实入口。** 执行 `.agents/skills/verify-nix-config/scripts/verify.sh darwin-build`。helper 以 `just --set profile <host> bd` 调用，构建 `darwinConfigurations.<host>` 的 system toplevel，命令退出码为 `0`
- **检查差异。** 在 `transcript.log` 里读 nh 打印的新增、删除和版本变化清单，末尾有 `PATHS`、`SIZE`、`DIFF` 三行汇总。这三行夹着 ANSI 颜色码，直接 `grep 'PATHS:'` 匹配不到，要先 `sed -E 's/\x1b\[[0-9;]*m//g'` 去掉颜色。汇总不能证明具体配置变化，继续比较新旧闭包与受影响的激活脚本；无法归因的差异阻断 switch
- **确认无切换。** 读取 `summary.json`，`shared_profile_links_unchanged` 为 `true`
- **保留 proof。** 保存 helper 输出的 evidence 目录：`transcript.log`、`summary.json`、`doctor.txt`、`metadata.txt`（含 Git revision 与工具版本）、`working-tree.txt` 与前后链接快照

## Gotchas

- `just bd` 会构建系统 derivation，但不会更新 `/run/current-system`
- 闭包差异不展示 Homebrew 声明和 activation 脚本的全部内容；系统切换前还需检查相关配置变化
- 其他主机按仓库规则轻量求值，本机 build 成功不能证明其他架构可构建
- 构建成功不授权 `just sw`
