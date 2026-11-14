# delegate 原型结论

> 原型，不进 main。正式实现见（待定）`sb delegate`。

验证对象：本机 mio 派发，节点 yuuko 执行；目标仓库为私有测试仓库，共 4 个真实任务（A–D）。

## 回答的问题

1. **只经 SSH 能否启动 VM、跑完 agent：能。**
   - 任务 A 开始时主 VM 处于停止状态；worker 里的 `sb run` 自动启动它（日志：`主 VM sb-main 已存在但处于停止状态，正在启动...`，`Started sb-main (0.5s)`），随后 agent 跑完、worker 推送并开 PR。全程没有在节点上开终端。
   - worker 必须在补全环境后运行：先加 nix 的几个 `bin` 目录到 `PATH`，再 `eval "$(mise env -s bash)"`，否则找不到 `msb`、`sec-run`。
   - 无人登录场景：**未验证**（验证期间节点控制台一直有用户登录）。
   - 「冷」只覆盖到「VM 已存在但已停止」，没有覆盖「VM 不存在、首次创建」。

2. **耗时**（秒；`fetch` 含 bare 仓库首次 clone）

   | 用例 | 说明 | fetch_s | agent_s | deliver_s |
   |---|---|---|---|---|
   | A | 冷：VM 已停止、仓库缓存为空；pi | 3 | 44 | 7 |
   | B | 热：VM 在运行、缓存已有；pi | 1 | 22 | 6 |
   | C | 热；omp，改一行 | 1 | 13 | 6 |
   | D | 热；pi，只读不改（失败路径） | 1 | 13 | 2 |

   - 时间几乎全花在 agent。冷/热的差别：fetch 3s 对 1s，VM 启动约 0.5s；对这个很小的测试仓库，冷启动额外开销只有几秒，被 agent 耗时盖住。大仓库的首次 clone 没测。
   - 交付约 6–7s（`push` + `gh pr create` + 删除 worktree）。
   - `run` 本身（复制脚本 + 派发）约 1.4s 返回。

3. **agent 是否遵守交付约定：A/B/C/D 全部遵守。**
   - A/B/C：只做了 `git commit`（A 两个提交，B、C 各一个）；推送前 worker 没有检测到远端已有任务分支，也没有检测到分支被切走（日志里无对应警告）；测试仓库的分支与 PR 列表里只有 worker 创建的那些。
   - D（要求不改不提交）：无提交，worker 判定 `no_commits`，没有开 PR，worktree 保留。
   - 样本只有 4 个且任务都很小，不能证明「稳定」；约定靠提示词，没有机制保证。
   - A 的最后一条回复清楚说明了做了什么、怎么验证的，可直接作为 PR 正文。

4. **接口体验**
   - `-f` 文件、文字参数、参数覆盖（`git@` 形式的 `--repo`、`--base`、`--branch`、`--agent omp`）都按预期工作；`--repo` 被规范成 https 形式。
   - 未推送提交、无上游两种拒绝都在连节点前报错，提示可直接照做；节点任务数不变。
   - `tasks --json`、`log <id> --json` 的结构对脚本友好（`.meta.status`、`.output`）；表格形式的 `tasks` 够用。
   - 不便：
     - 没有「等待任务结束」，只能轮询 `log --json`。
     - 未推送检查只看当前分支，不看 `--base`；`--base` 与当前分支不同时检查对象不对。
     - 每次 `run`/`tasks`/`log` 都复制一次脚本，多一次 SSH 往返。
     - `log` 的日志里混有 `sb` 自己的提示行，guest 的 stderr 不会回流（沙箱已知行为）。

## 正式实现要带走的结论

- worker 环境：`cd ~`，补 `PATH`（`~/.nix-profile/bin` 等），再 `eval "$(mise env -s bash)"`；启动前断言 `sb msb sec-run gh git jq` 都在。节点上 `ssh` 与 `nohup` 的默认环境都没有这些。
- bare 仓库缓存：clone 后必须把 `remote.origin.fetch` 改成 `+refs/heads/*:refs/remotes/origin/*`，否则 `fetch --prune` 会删掉尚未推送的任务分支。
- `git worktree add` 要加 `--no-track`，避免任务分支的上游被设成 `origin/<base>`。
- 同一仓库的 clone/fetch/worktree add 用 `lockf -k <锁文件>` 串行（节点没有 `flock`，macOS 自带 `lockf`）。
- 派发后台 worker：`nohup caffeinate -i … </dev/null >>log 2>&1 &`，三个标准流都重定向，SSH 才能立刻断开。`caffeinate` 的防睡眠效果这次没有单独验证。
- 设置 `LC_ALL=en_US.UTF-8`：后台环境没有 locale，截断 PR 标题时可能切断多字节字符。
- 交付由脚本做：用 `origin/<base>..HEAD` 的提交数判定 `no_commits`；push 前检查远端是否已有任务分支，可以发现 agent 违规 push。
- 沙箱隔离成立：任务 worktree 里的 agent 看不到 `~/Code` 下的其他目录（节点上放了金丝雀目录，沙箱里不可见，宿主上仍在）；它能看到自己的任务目录和仓库缓存 bare repo，看不到其他任务的目录与 `prompt.md`。
- 沙箱里 `~` 是 `/root`，不是宿主家目录；排查路径问题或写隔离测试要用宿主绝对路径。
- 任务 id 在节点上要校验格式，防止路径穿越。
- `sb run` 在非 TTY 下只回传 agent 的 stdout；PR 正文取 stdout 的最终回复，效果可用。

## 未覆盖

- 并发任务（同仓库、不同仓库）与锁的实际竞争。
- 包缓存层、`sb gc`、任务目录与 worktree 的清理。
- 无人登录时启动 VM。
- VM 首次创建（不存在）的冷启动。
- 失败原因 `env_missing`、`fetch_failed`、`base_missing`、`push_failed`、`pr_failed`、`worker_crashed`、`agent_failed` 没有触发过。
- 大仓库的首次 clone 耗时；`-f -` 从标准输入读取任务。
