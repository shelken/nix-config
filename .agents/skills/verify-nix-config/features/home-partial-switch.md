# Home partial switch

Home partial switch 让用户通过 `just hm` 激活当前机器配置中的 Home 子结果，更新用户 profile、文件、用户服务和 activation 历史，不切换 Darwin system generation

## Sub-features

- `home-switch-authorized` 仅在任务明确授权实际应用时运行
- `home-switch-command` 运行仓库公开的 `just hm` 入口
- `home-switch-system-stable` 保持 Darwin current-system 与 system profile 不变
- `home-switch-side-effects` 从真实用户入口确认包、文件或用户服务结果
- `home-switch-idempotent` 再次运行同一配置不复活已删除声明

## How to get to it (user POV)

- 在仓库根目录运行 `just hm`
- 本地 secrets 联动入口为 `just hm-dev`，它是独立入口，只有任务要求该 override 时才使用

## Driving it with Bash

Preconditions:

- 任务明确授权修改当前用户 Home 状态
- `verify.sh doctor` 输出 `doctor=ok`
- `just hm-build` 已成功，构建差异已审查
- 当前没有其他 system/Home switch 正在运行
- 当 system build diff 移除系统用户包环境时，已先完成对应的 `just sw`

- **创建 proof 目录。** 设置 `EVIDENCE_DIR=${TMPDIR:-/tmp}/verify-nix-config-evidence/<run-id>-home-switch` 并创建目录
- **记录前态。** 运行 `.agents/skills/verify-nix-config/scripts/verify.sh snapshot "$EVIDENCE_DIR/before-links.txt"`
- **运行真实入口。** 在 Bash 中执行 `set -o pipefail; just hm 2>&1 | tee "$EVIDENCE_DIR/transcript.log"`，保留 `PIPESTATUS[0]`，要求退出码为 `0`
- **记录后态。** 运行 `verify.sh snapshot "$EVIDENCE_DIR/after-links.txt"`。`/run/current-system` 与 system profile 行保持不变，Home generation/profile 行按新 activation 更新
- **确认副作用。** 从变更对应的用户入口验证，例如 `zsh -lic 'whence -a <command>'`、读取 Home 管理文件、查询用户服务。结果写入 `$EVIDENCE_DIR/side-effects.txt`
- **确认删除。** 对被撤销声明检查目标确实不存在，不能用 PATH 中更早的替代命令掩盖旧文件
- **确认幂等。** 变更要求防复活时再次运行 `just hm`，重复记录 transcript 与 side effect，system 链接仍不变

## Gotchas

- 此入口修改共享用户状态，无法与另一个 Home drive 隔离并行
- activation 日志成功只能证明脚本退出，不能证明命令解析、文件删除或服务状态正确
- system 用户包环境中的旧命令不能由 Home switch 删除，必须先完成系统迁移
- 自动 rollback 会覆盖用户当前状态，不属于 cleanup，只能在明确授权后执行
