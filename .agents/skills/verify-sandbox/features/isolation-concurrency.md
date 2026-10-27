# 隔离与并发上下文

每次启动得到一个只看得到当前项目的执行上下文；多个上下文同时运行时互不打断，退出后不留残留

## Sub-features

- `iso-neighbor` 上下文内看不到相邻项目
- `iso-private-net` 未授权的私网目标无应用层响应
- `iso-secret` secret 占位符在出口被替换（无自动化检查，手工观察）
- `iso-worktree` worktree 内可 `git commit`，提交在宿主可见
- `conc-start` 多个上下文同时启动，槽位互不相同
- `conc-exit` 一个上下文退出不影响其他
- `conc-clean` 全部退出后 guest 内无残留上下文目录、netns、veth

## How to get to it (user POV)

- 在不同终端各运行一次 `omp-sb` 或 `sb run`
- 在 worktree 目录运行 `omp-sb`

## Driving it with verify.sh

Preconditions:

- doctor 通过；只有 `$V smoke` 自带一次性 VM，其余几步要主 VM 在运行（`$V sb up`）
- 在 guest 里用 `jq`、`ip` 之类基础工具要先 `. /run/sandbox-config/current/guest-env.sh`；`$V msb exec` 的默认 PATH 里没有它们，命令找不到时计数会得 0，造成假通过
- 定义 `G='. /run/sandbox-config/current/guest-env.sh'` 与 `count() { $V msb exec sb-main -- bash -c "$G; ls /run/sandbox/contexts/*/meta.json 2>/dev/null | wc -l"; }`

- **隔离边界三项。** 运行 `$V run smoke -- $V smoke`。`smoke.out` 末尾为「隔离边界冒烟测试全部通过」，`smoke.rc` 为 `0`。注意它的局限：`iso-secret` 没有自动化检查（secret 占位符替换只在手工验证时观察），相邻项目不可见在 smoke 里靠 `--tmpfs /tmp`，真实项目在 `~/Code`，靠的是 `--tmpfs $HOME`
- **并发启动。** 运行 `for i in 1 2 3; do $V sb run bash -c 'sleep 15; echo DONE' > "$EVIDENCE/conc$i.out" 2>&1 & done`，轮询 `count` 到 `3`（不要写死 `sleep`，冷热 VM 差别很大），再运行 `$V msb exec sb-main -- bash -c "$G; jq -r '\"slot=\(.slot)\"' /run/sandbox/contexts/*/meta.json | sort"`。得到 `slot=0`、`slot=1`、`slot=2`，互不相同
- **一个先退出，其余不受影响。** 同时启动三个上下文，其中一个 `sleep 4; echo SHORT_DONE`，另两个 `sleep 20`，并分别记下 `$!`。`count` 到 `3` 后 `wait` 短的，`count` 变为 `2`；再 `wait` 另两个，它们的退出状态都是 `0` 且各自输出 `LONG_A`、`LONG_B`。不要用 `kill` launcher 的 pid 制造「提前退出」：launcher 的 bash 在前台子进程运行期间收到 TERM 会推迟处理，命令照常跑完，三个退出码都是 `0`，分不出被打断与否
- **无残留。** 全部结束后运行 `$V msb exec sb-main -- bash -c "$G; echo \"ls-A=\$(ls -A /run/sandbox/contexts | tr '\n' ' ') netns=\$(ip netns list | wc -l) vth=\$(ip -o link | grep -c vth || true)\""`。`ls-A=.slot.lock`（这个槽位锁文件是永久的，不算残留）、`netns=0`、`vth=0`。并发运行中同一命令的 `netns` 与 `vth` 非零，说明 `ip` 可用、这两个 0 不是命令缺失造成的

## Gotchas

- 私网断言必须看应用层响应：msb 会伪造 TCP 握手，ping 或端口探测不可信
- 后台任务的输出要写进 evidence，否则无法区分「没启动」和「被打断」
- `$EVIDENCE` 由 `$V paths` 给出
- 在 worktree 目录运行 `omp-sb` 要求 worktree 与它的 git common dir 都在 `sb.yaml` 的 `mount_roots` 内，否则直接报错退出
