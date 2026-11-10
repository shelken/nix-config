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
