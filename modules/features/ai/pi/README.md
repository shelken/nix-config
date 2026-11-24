# Pi 配置

## 自动压缩阈值

`settings.json` 的 `compaction.modelOverrides` 由 `just ai::pi-compaction` 回填，不要手改；增删 `enabledModels` 后跑一次，阈值与预留下限改 `utils/script/just/sync_pi_compaction.py` 开头

## 后台 shell

选用 `pi-background`：任务结束即在下一次模型调用前经 `steer` 投递（`@pify/shell-background` 会攒到整轮结束才发，反复唤醒已汇报的子代理）；也不用精简版 `@shelken/pi-background-lean`，其压短规则后模型会改成重定向并 `sleep` 轮询，单次多余往返成本远高于每轮省下的 ~800 缓存 tokens

- 前台 `bash` 超 120 秒自动转后台（阈值写死在插件源码，无配置项），`timeout` 到点同样转后台而非杀进程
- 后台结果仅带末 20 行与完整日志路径，会话结束时仍在运行的后台任务会被杀掉

## 输出截断

`extensions/line-cap.ts` 补齐 pi 内置 bash 的限制（内置只限总量、不限单行且仅留尾部）；被截原文按内容哈希存于 `~/.pi/agent/line-cap/`（不自动清理），不处理 `read` 以免模型照残缺源码行做 `edit`
