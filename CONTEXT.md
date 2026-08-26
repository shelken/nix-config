# 领域模型 (Context)

基于 Nix Flakes 与 nix-darwin / Home Manager 的多平台配置与任务调度领域知识。

## 领域词汇 (Ubiquitous Language)

- **任务 (Task)**: 声明式的轻量级定时工作单元，由调度规则、运行权限、运行时依赖与执行脚本组成。
- **调度规则 (Schedule)**: 触发任务执行的时间条件，分为**日历时间 (`when`)**与**固定间隔 (`every`)**，两者严格互斥。
- **运行层级 (Permission Tier)**:
  - **用户任务 (`user = true`)**: 运行于当前登录用户的会话环境，调度由 Home Manager 的 User LaunchAgent (`user domain`) 接管。
  - **系统任务 (`user = false`)**: 运行于 root 权限环境，调度由 nix-darwin 的 System LaunchDaemon 接管。
- **运行时依赖 (`packages`)**: 任务脚本执行时依赖的 CLI 工具包列表，通过 `writeShellApplication.runtimeInputs` 注入隔离的 `PATH`。
- **任务中心 CLI (`task`)**: 统一的任务运维入口，提供 `task ls`（列出任务及调度规则）、`task run <name>`（手动执行）、`task log <name>`（查看日志）等子命令。

## 核心实体与不变量

1. **单文件即任务**: 在 `hosts/<host>/tasks/<name>.nix` 放置文件即自动注册，文件名即任务标识符 `<name>`。
2. **三位一体自动生成**:
   - 底层可执行脚本：`task-<name>`
   - 调度配置：LaunchAgent / LaunchDaemon plist
   - 日志挂载：标准输出与错误自动重定向至独立日志文件
3. **互斥不变量**: 每个任务必须且只能在 `when` 或 `every` 中指定一种调度策略。
4. **无侵入接入**: 机器主配置 `hosts/<host>/default.nix` 零接线，自动发现并加载当前机器专属任务。
