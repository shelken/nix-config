# 声明式轻量定时任务

日期: 2026-08-26

定时任务（日志清理、垃圾回收等）散落在各模块里，书写繁琐、没有统一视图、环境隔离脆弱。现在一个任务即为 `hosts/<host>/tasks/<name>.nix` 里的一个属性集，添加后自动注册，主机配置零接线。脚本由 `writeShellApplication` 生成，依赖映射为 `runtimeInputs` 并自动通过 shellcheck 校验；`user = true` 映射为 Home Manager LaunchAgent，`user = false` 映射为 nix-darwin LaunchDaemon；日志自动重定向到标准 Logs 目录。每个任务必须且只能指定 `when`（日历时间）或 `every`（固定间隔）之一。`task ls`、`task run`、`task log` 在运行时读取 launchd plist，提供统一的查看与调试入口

## 考虑过的替代方案

- **保留手动开关**：多一层间接和样板代码，违背「加文件即生效」
- **自制 Cron 解析引擎**：增加维护负担，且丢失 launchd 唤醒后补跑的语义

## 后果

只适用于纯脚本型定时任务；具有复杂生命周期的服务仍作为独立功能实现
