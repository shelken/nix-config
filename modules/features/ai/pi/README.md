# Pi 配置

Posthorse 必须排在 `pi-execution-time` 前面，避免自动 compact 后出现工具消息配对错误

- [#244：根因、验证结果与升级限制](https://github.com/shelken/nix-config/issues/244)

## 自动压缩阈值

`settings.json` 的 `compaction.modelOverrides` 由 `just ai::pi-compaction` 回填，不要手改。增删 `enabledModels` 后跑一次。压缩节点与预留下限在 `utils/script/just/sync_pi_compaction.py` 开头，改那里即可。

## 后台 shell

用 `pi-background` 提供后台命令：`bg_run` 启动、`bg_status` 查看、`bg_kill` 停止，`/bg` 看输出。

选它的原因是投递方式。后台任务一结束，结果就在下一次模型调用前送达（pi 的 `steer` 投递）。之前用的 `@pify/shell-background` 把结果攒到整个 run 结束才发，子代理汇报完之后还会被迟到的结果逐条唤醒。

与之前不同的行为：

- 前台 `bash` 运行超过 120 秒自动转后台。这个阈值写死在插件源码里，没有配置项
- `bash` 的 `timeout` 到点后不杀进程，而是把命令转到后台
- 后台结果只带日志最后 20 行，完整日志路径在结果里
- 会话结束时仍在运行的后台任务会被杀掉

## 输出截断

`extensions/line-cap.ts` 在 bash 类输出进模型之前做两件事：

- 单行超过 768 字符的部分换成 `…[+N chars]`
- 总量超过 50KB 或 2000 行时保留开头 20% 和结尾 80%，中间用 `[… N lines omitted …]` 标记

pi 内置 bash 只限总量、不限单行，且超限时只留尾部。

处理位置按消息来源分两处：

- `bash`、`bg_status` 的结果挂 `tool_result`。pi 在这之前已经把输出截成尾部，开头只在 `details.fullOutputPath` 指向的文件里，所以要回读那个文件再重排
- `pi-background` 的后台结果和用户 `!cmd` 的输出不经过 `tool_result`，挂 `context`

被截掉的内容都能取回：pi 截断过的输出看结果末尾的 `Full output:` 路径；其余情况原文按内容哈希存在 `~/.pi/agent/line-cap/`，不会自动清理。

不处理 `read`：截断源码行会让模型照残缺文本去 `edit`。
