# 首次启动

用户在项目里第一次运行 `omp-sb` 或 `sb` 命令时，主 VM 和数据卷被自动创建，工具自动补齐一次，之后的启动直接复用

## Sub-features

- `first-create` 数据卷与主 VM 不存在时自动创建
- `first-sync` 只有新建 VM 时自动执行一次 `sb sync`
- `first-ready` `sb status` 报告 Running、上限一致、无缺失工具
- `reuse` 第二次启动复用现有 VM，几秒内完成
- `stdout-clean` `sb run` 的 stdout 只有命令自身输出

## How to get to it (user POV)

- 在项目目录运行 `omp-sb`
- 运行 `sb run <命令>` 或 `sb shell`
- 运行 `sb up`

## Driving it with verify.sh

Preconditions:

- 隔离环境内没有任何 VM 与卷：`$V msb ls` 输出 `No sandboxes found.`

- **首次运行。** 运行 `$V run first -- $V sb run uname -m`。`first.out` 只有 `aarch64`；`first.err` 依次出现「数据卷 … 不存在，正在创建」「正在创建主 VM」「首次创建自动执行 sb sync」「工具与插件补齐成功」；`first.rc` 为 `0`
- **就绪状态。** 运行 `$V run status -- $V sb status`。输出含 `VM 状态: Running`、`上限一致: consistent`、`缺失工具: 无`
- **复用。** 再运行 `$V run reuse -- $V sb run true`。stderr 为「正在运行且能力上限一致，复用现有 VM」，不出现 sync 输出
- **共用层未重复下载。** 首次运行前后各取 `du -sk ~/Data/sandboxes/mise/aarch64-linux`。mise 工具已装齐时，增量只来自插件 Bun 缓存，第二次起不再增长

## Gotchas

- `first.err` 出现「未在沙箱内找到 sync-guest.sh」说明挂的不是本分支的发布配置，检查 `$V doctor` 的「隔离配置已发布」
- 只删 VM 不删卷再启动，也走「首次创建」分支并自动 sync；重建（上限变化）不自动 sync
