# 声明式轻量定时任务

定时任务（日志清理、垃圾回收等）原先散落在各模块里，书写繁琐、没有统一视图、环境隔离脆弱。现在主机专属任务写成 `hosts/<host>/tasks/<name>.nix` 里的属性集即可自动注册，功能也可经 `shelken.tasks.<name>` 声明；框架实现在本目录，`ntask` CLI 运行时读取 launchd plist 提供查看与调试入口。使用步骤见 [定时任务用户指南](../../../../docs/user-guide/01-tasks.md)

## 设计约束

- `when`（日历时间）与 `every`（固定间隔）不能同时声明；两者都不设时生成无调度 plist，作为手动任务由 `ntask run` 触发
- 包装脚本默认以 launchd 同款隔离环境执行：固定 `PATH` 为 `packages` 加上 `/usr/bin:/bin:/usr/sbin:/sbin`，经 `env -i` 仅保留最小白名单环境变量，工作目录切到 `/`，关闭标准输入。手动 `ntask run` 与定时唤起环境一致；加 `--as-launchd` 时额外注入 `SHELKEN_TASK_LAUNCHD=1` 以验证抖动与通知
- 具有复杂生命周期的服务作为独立功能实现，不走本框架

## 编写建议

- 任务涉及外部项目且项目已有 `mise.toml` 时，`packages` 优先只声明 `mise` 与少量宿主机基础工具（如 `git`），项目内命令先 `cd` 进仓库再通过 `mise exec --` 执行。这样项目工具链由项目自身单源维护，避免业务仓升级工具后与本仓 `packages` 漂移

## 考虑过的替代方案

- 保留手动开关：多一层间接与样板，违背「加文件即生效」
- 自制 Cron 解析引擎：维护负担大，丢失 launchd 唤醒后补跑的语义
