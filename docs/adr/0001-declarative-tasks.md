# 0001. 声明式轻量定时任务系统设计

## 状态

已采纳 (Accepted)

## 背景与问题

在多平台与多主机的配置管理中，定时任务（如日志清理、垃圾回收）分散在不同模块中，存在书写繁琐、缺乏统一视图、环境隔离脆弱等问题。

## 决策

1. **单一文件声明**：在 hosts/<host>/tasks/<name>.nix 下放置纯属性集，约定优于配置，自动注册。
2. **自动代码生成**：
   - 依赖与脚本：使用 pkgs.writeShellApplication，将 packages 映射为 runtimeInputs，自动执行 shellcheck 检查。
   - 调度配置：user = true 映射到 Home Manager LaunchAgent；user = false 映射到 nix-darwin LaunchDaemon。
   - 日志重定向：自动挂载 StandardOutPath 与 StandardErrorPath 至标准 Logs 目录。
3. **统一入口 CLI (`task`)**：
   - `task ls`：运行时读取 `space.ooooo.task-*` launchd plist，展示任务名、权限层、调度规则与日志路径
   - `task run <name>`：调度底层 `task-<name>` 脚本
   - `task log <name>`：快速查看或追踪任务日志

## 考虑过的替代方案

- **保留手动开关**：增加间接层与样板代码，违背加文件即生效的原则。
- **自制 Cron 解析引擎**：增加维护负担，且丢失 launchd 的唤醒补跑语义。

## 影响与代价

- **积极影响**：新增任务仅需 5 行配置，开发体验高度简化，具备自省与排障能力。
- **边界**：仅适用于纯脚本型定时任务。具备复杂生命周期的重型服务依然保持独立模块形式
