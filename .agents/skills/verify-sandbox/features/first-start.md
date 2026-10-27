# 首次启动

用户在项目里第一次运行会启动主 VM 的命令（`omp-sb`、`sb run`、`sb shell`、`sb up`）时，主 VM 和数据卷被自动创建，工具自动补齐一次，之后的启动直接复用。`sb status`、`plan`、`trust`、`down`、`rm` 不建 VM

## Sub-features

- `first-create` 数据卷与主 VM 不存在时自动创建
- `first-sync` 只有新建 VM 时自动执行一次 `sb sync`
- `first-ready` `sb status` 报告 Running、上限一致、无缺失工具
- `reuse` 第二次启动复用现有 VM，不再 sync

## How to get to it (user POV)

- 在项目目录运行 `omp-sb`
- 运行 `sb run <命令>` 或 `sb shell`
- 运行 `sb up`

## Driving it with verify.sh

Preconditions:

- 隔离环境内没有任何 VM 与卷：`$V cleanup` 之后重新 `$V setup`，`$V msb ls` 输出 `No sandboxes found.`，`$V msb volume ls` 输出 `No volumes found.`

- **首次运行。** 运行 `$V run first -- $V sb run uname -m`，再看 `first.rc`。`first.out` 只有 `aarch64`；`first.err` 依次出现「数据卷 … 不存在，正在创建」「正在创建主 VM」「创建并启动成功」「首次创建自动执行 sb sync」「工具与插件补齐成功」；`first.rc` 为 `0`。`sb run` 的 `rc` 为 0 不证明 sync 成功，首次 sync 失败只多一行「首次工具自动补齐未全部完成」，两者分开断言
- **就绪状态。** 运行 `$V run status -- $V sb status`。`status.out` 含 `VM 状态: Running`、`上限一致: consistent`、`缺失工具: 无`。「缺失工具」只统计 mise 工具，不反映插件是否装好，插件看 `sync.md` 的私有插件一步
- **复用。** 再运行 `$V run reuse -- $V sb run true`。`reuse.err` 含「正在运行且能力上限一致，复用现有 VM」，不含「补齐」，`reuse.rc` 为 `0`
- **共用层增量。** 首次运行前后各取 `du -sk "${SB_MISE_HOST_DIR:-$HOME/Data/sandboxes/mise/aarch64-linux}"`。共用层已装齐时，增量在几 KB 量级，复用之后不变；mise 工具真缺时下载会落在这个目录里，增量会大得多

## Gotchas

- `first.err` 出现「未在沙箱内找到 sync-guest.sh」说明挂的不是本分支的发布配置，检查 `$V doctor` 的「隔离配置已发布」。这个警告不让 `sb run` 失败，症状是「缺失工具」
- 只删 VM 不删卷再启动，也走「首次创建」分支并自动 sync；重建（上限变化）不自动 sync
