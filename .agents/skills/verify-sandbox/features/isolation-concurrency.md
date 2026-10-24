# 隔离与并发上下文

每次启动得到一个只看得到当前项目的执行上下文；多个上下文同时运行时互不打断，退出后不留残留

## Sub-features

- `iso-neighbor` 上下文内看不到相邻项目
- `iso-private-net` 未授权的私网目标无应用层响应
- `iso-secret` secret 占位符在出口被替换
- `iso-worktree` worktree 内可 `git status`、`git commit`，提交在宿主可见
- `conc-start` 多个上下文同时启动，槽位互不相同
- `conc-exit` 一个上下文退出不影响其他
- `conc-clean` 全部退出后 guest 内无残留上下文目录、netns、veth

## How to get to it (user POV)

- 在不同终端各运行一次 `omp-sb` 或 `sb run`
- 在 worktree 目录运行 `omp-sb`

## Driving it with verify.sh

Preconditions:

- doctor 通过；冒烟测试自带一次性 VM，不需要先 `sb up`

- **隔离边界四项。** 运行 `$V smoke`。`smoke.out` 末尾为「隔离边界冒烟测试全部通过」，`smoke.rc` 为 `0`
- **并发启动。** 运行 `for i in 1 2 3; do $V sb run bash -c 'sleep 8; cat /proc/net/route | head -2' > "$EVIDENCE/conc$i.out" 2>&1 & done; sleep 3; $V msb exec sb-main -- bash -c 'cat /run/sandbox/contexts/*/meta.json'`。3 份 meta 的 `slot` 互不相同
- **提前退出。** 并发期间运行 `$V msb exec sb-main -- bash -c 'kill $(jq -r .pid /run/sandbox/contexts/*/meta.json | head -1)'`。其余两个后台任务退出码为 `0`
- **无残留。** 全部结束后运行 `$V msb exec sb-main -- bash -c 'ls /run/sandbox/contexts | wc -l; ip netns list | wc -l; ip -o link | grep -c vth'`。三个数都是 `0`

## Gotchas

- 私网断言必须看应用层响应：msb 会伪造 TCP 握手，ping 或端口探测不可信
- 后台任务的输出要写进 evidence，否则无法区分「没启动」和「被打断」
- `$EVIDENCE` 由 `$V paths` 给出
