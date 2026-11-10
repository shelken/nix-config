# 共用层回收

`sb gc` 用户主动触发，回收共用 mise 安装层里不再被引用的工具版本与插件缓存。默认只预估并打印 `[gc-dry]`，加 `--yes` 才真删。与 `sb sync` 的补齐语义分离：补齐只装缺失项、失败可无限重试，删除会破坏这个性质，所以清理是独立命令。

## Sub-features

- `gc-dry-no-delete` 无参 `sb gc` 只打印预估，共用层大小不变
- `gc-yes-removes` `sb gc --yes` 真删并输出汇总行，共用层变小
- `gc-git-cache-survives` `*.git/`、`@G@*`、`@GH@*` 与仍被 `bun.lock` 引用的条目完好
- `gc-busy-rejected` 有上下文在运行时拒绝回收，退出码非零
- `gc-sync-idempotent` gc 之后 `sb sync` 仍成功，不重新下载已装项

## How to get to it (user POV)

- 宿主运行 `sb gc` 看预估，确认后 `sb gc --yes` 执行
- 不会自动触发：VM 创建、重建、复用都不执行 gc

## Driving it with verify.sh

Preconditions:

- 首次启动已完成（`$V sb up`）
- 共用层目录 `M=$(jq -r .mise.host_dir "$WORK/sb-config.json")`。harness 不隔离它，gc 删的是真实共用层

- **dry-run 不删东西。** 先记录 `du -sk "$M"`，再运行 `$V run gc-dry -- $V sb gc`。`gc-dry.rc` 为 `0`，`.out` 含 `[gc-dry]`，不含 `[gc] 删除`；`du -sk "$M"` 与记录值相同
- **`--yes` 生效。** 运行 `$V run gc-yes -- $V sb gc --yes`。`gc-yes.rc` 为 `0`，`.out` 含 `[gc] 删除` 与 `汇总: 回收` 行；`du -sk "$M"` 小于 gc-dry 时记录的值
- **git 缓存幸存。** gc 前后各运行一次 `$V msb exec sb-main -- bash -c 'ls /opt/sandbox-mise/cache/bun-cache/ | grep -c "\.git$\|@G@\|@GH@"'`，两个数字相同且不为 `0`。若共用层本来就没有 git 条目，在测试项目写带 git 源的 `mise.toml` 并 `sb run mise install` 造一个，结束后删除
- **busy 拒绝。** `$V sb run sleep 120 &` 起一个长上下文，立刻运行 `$V run gc-busy -- $V sb gc --yes`。`gc-busy.rc` 非 `0`，`.err` 含「上下文」；`wait` 回收后台上下文
- **sync 幂等不受影响。** gc 后立刻运行 `$V run sync-after-gc -- $V sb sync`。`sync-after-gc.rc` 为 `0`，`.out` 或 `.err` 含「工具与插件补齐成功」，且没有重新下载登记工具的迹象

## Gotchas

- gc 写真实共用层，删掉的是宿主上所有 VM 共用的版本。`mise prune` 只删脱离 tracked-configs 引用的版本，项目 `mise.toml` 仍在用的不动
- dry-run 不跑 `mise prune`：它的判定依赖 tracked-configs，与真实删除结果不一定一致，所以 dry-run 只列 installs 下各完整版本目录的占用并标 `prune 候选`，不计入可回收合计
- 判定 bun 条目是否仍被引用靠 `bun.lock` 文本里的 `"包名@版本"`。插件从未安装过（没有 `bun.lock`）时整个裁剪跳过，不清空缓存
- 有上下文在运行时 `sb gc` 直接拒绝，不会等它退出；先关掉 Agent 再回收
- mise 升级若改变 tracked-configs 机制，`gc-dry-no-delete` 与 `gc-yes-removes` 要重验
