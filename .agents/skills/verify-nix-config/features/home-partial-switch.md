# Home partial switch

Home partial switch 让用户通过 `just hm` 激活当前机器配置中的 Home 子结果，更新用户 profile（包括默认 Nix profile `~/.nix-profile`）、文件、用户服务和 activation 历史，不切换 Darwin system generation

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
- `verify.sh doctor` 输出 `doctor=ok`，将其 `host` 字段设为 `HOST_ATTR`，后续命令显式使用该主机
- `just --set profile "$HOST_ATTR" hm-build` 已成功，构建差异已审查
- 当前没有其他 system/Home switch 正在运行
- 当 system build diff 移除系统用户包环境时，已先完成对应的 `just sw`

- **创建 proof 目录。** 设置 `EVIDENCE_DIR=${TMPDIR:-/tmp}/verify-nix-config-evidence/<run-id>-home-switch` 并创建目录
- **记录前态。** 运行 `.agents/skills/verify-nix-config/scripts/verify.sh snapshot "$EVIDENCE_DIR/before-links.txt"`，并另外 `readlink -f ~/.nix-profile` 记下默认 profile 的目标，`snapshot` 不记录它
- **运行真实入口。** 在 Bash 中执行 `set -o pipefail; just --set profile "$HOST_ATTR" hm 2>&1 | tee "$EVIDENCE_DIR/transcript.log"`。紧接着保存 `PIPESTATUS[0]` 到退出码证据，要求为 `0`。退出码非零不代表什么都没变：激活顺序是先动 profile 与文件、最后加载 launchd，launchd 阶段失败时前面的改动已经生效，且激活最前面会删除 `~/.gitconfig`
- **记录后态。** 运行 `verify.sh snapshot "$EVIDENCE_DIR/after-links.txt"`。系统两条链接保持不变；快照里的 symlink 只解一跳（如 `home-manager-622-link`），再 `readlink -f` 解到 store 路径并确认与本次构建结果一致；重复应用同一配置无需产生新路径
- **确认副作用。** 从变更对应的用户入口验证，例如 `zsh -lic 'whence -a <command>' 2>&1`、读取 Home 管理文件、查询用户服务。非终端下该命令会向 stderr 打印 `can't change option: zle`，退出码仍为 `0`，这不是失败。结果写入 `$EVIDENCE_DIR/side-effects.txt`
- **确认删除。** 对被撤销声明检查目标确实不存在，不能用 PATH 中更早的替代命令掩盖旧文件
- **确认幂等。** 变更要求防复活时再次运行 `just --set profile "$HOST_ATTR" hm`，另存 transcript 与副作用结果，系统链接仍不变。只有 `home-files` 里的链接会被清理；activation 脚本自己写出的文件（如 neovim、karabiner 相关）不受管，不会因为再跑一次而消失

## Gotchas

- 此入口修改共享用户状态，无法与另一个 Home drive 隔离并行
- activation 日志成功只能证明脚本退出，不能证明命令解析、文件删除或服务状态正确
- 旧命令的滞留位置是 `environment.systemPackages` 的 `/run/current-system/sw/bin`，在 `~/.nix-profile/bin` 之后参与 `PATH`；Home switch 删不掉它们，必须先完成系统迁移。`/etc/profiles/per-user` 被 doctor 明令禁止，不是滞留位置
- `just hm` 路径没有自动 rollback；`just rollback` 回滚的是系统 profile。想回到之前的 Home 状态要另行经授权操作，不属于 cleanup
