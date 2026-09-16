# Darwin system switch

Darwin system switch 让用户通过 `just sw` 构建并激活完整机器配置，更新 system generation、系统服务、设置和内嵌 Home 激活结果

## Sub-features

- `darwin-switch-authorized` 仅在任务明确授权完整系统变更时运行
- `darwin-switch-command` 运行仓库公开的 `just sw` 入口
- `darwin-switch-generation` 更新 current-system 与 system profile 到同一个新 generation
- `darwin-switch-home` 运行系统内嵌 Home activation
- `darwin-switch-side-effects` 从系统或用户入口确认目标行为

## How to get to it (user POV)

- 在仓库根目录运行 `just sw`
- 需要回滚时仓库提供 `just rollback`，它是新的系统变更，必须单独授权

## Driving it with Bash

Preconditions:

- 任务明确授权完整 Darwin switch
- `verify.sh doctor` 输出 `doctor=ok`
- `verify.sh darwin-build` 成功，完整 diff 已审查且没有无法归因的系统变化
- 当前没有其他 system/Home switch 正在运行
- sudo 凭据与交互终端可用

- **创建 proof 目录。** 设置 `EVIDENCE_DIR=${TMPDIR:-/tmp}/verify-nix-config-evidence/<run-id>-darwin-switch` 并创建目录
- **记录前态。** 运行 `.agents/skills/verify-nix-config/scripts/verify.sh snapshot "$EVIDENCE_DIR/before-links.txt"`
- **运行真实入口。** 在交互式 Bash 中执行 `set -o pipefail; just sw 2>&1 | tee "$EVIDENCE_DIR/transcript.log"`，保留 `PIPESTATUS[0]`，要求退出码为 `0`
- **记录后态。** 运行 `verify.sh snapshot "$EVIDENCE_DIR/after-links.txt"`。current-system 与 system profile 指向新的同一 generation，Home profile/current-home 指向本次系统内嵌 Home activation
- **确认副作用。** 通过变更对应的真实入口查询系统设置、launchd 服务、Home 文件或 CLI，输出写入 `$EVIDENCE_DIR/side-effects.txt`
- **确认同源。** switch 后重跑 `verify.sh doctor`，要求系统 Home 与 `homeConfigurations` drvPath 仍相同

## Gotchas

- 此入口会应用工作树中的全部系统改动，目标 feature 构建成功不能替代完整 diff 审查
- switch 可能需要 sudo 和 launchd，不能放入无交互后台进程
- Homebrew、系统 LaunchDaemon 与系统设置只由完整 switch 应用，`just hm` 无法验证这些副作用
- 自动 rollback 不属于 cleanup；失败时保留 proof，先诊断再决定是否经授权回滚
