# Pi 配置

Posthorse 必须排在 `pi-execution-time` 前面，避免自动 compact 后出现工具消息配对错误

- [#244：根因、验证结果与升级限制](https://github.com/shelken/nix-config/issues/244)

## 自动压缩阈值

`settings.json` 的 `compaction.modelOverrides` 由 `just ai::pi-compaction` 回填，不要手改。增删 `enabledModels` 后跑一次。压缩节点与预留下限在 `utils/script/just/sync_pi_compaction.py` 开头，改那里即可。
