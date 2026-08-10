---
name: pi-extension-best-practice
description: 编写或审查任何 pi 插件的 factory、事件、命令、配置、日志或测试时使用
---

# pi 插件最佳实践

所有 pi 插件遵守一组通用边界: **轻量 factory、生命周期安全、数据边界、隔离验证**. Provider 再叠加模型门闩、网络和跨进程锁.

## 何时用

- 创建或修改 pi 插件的 factory、事件处理器、命令或 TUI
- 设计插件配置、缓存、日志和时间字段
- 编写插件测试、真实 Pi E2E 或审查生命周期安全
- 开发 provider 的 `session_start` / `model_select` 激活逻辑

## 拆分

- [session-start 规范](./session-start.md) — Provider 的 `session_start` / `model_select` 契约 (`activate`、模型门闩、`hasUI`、跨进程锁). 写或审 Provider 激活逻辑时加载.

## 通用原则

### Factory 与生命周期

- Factory 只做注册和内存初始化; 网络与同步重 IO 延迟到 `session_start` 或实际调用路径
- 优先复用 pi 内置 API、组件和转换函数; 只有现有能力无法表达协议或交互时才自建实现
- `ctx` / `ctx.ui` 属于当前生命周期; 跨事件异步链使用 fresh ctx，展示层失败不得破坏主流程

### 配置、存储与时间

- 全局配置放 `{pi-agent-dir}/extensions/<name>/config.json`; 项目配置放 `.pi/extensions/<name>/config.json` 并覆盖全局
- 缓存放 `{pi-agent-dir}/cache/<name>/`; 日志放 `{pi-agent-dir}/logs/<name>.log`; 测试使用临时目录
- 配置读写只投影已知键，更新时保留未知键; 凭据与业务缓存使用独立文件
- 时间存储与传输统一使用 UTC ISO 8601 (`Date.toISOString()`); 展示时按用户当前时区转换

### 命令与 TUI

- 有用户配置时提供 `/xxx config`，避免要求用户手改 JSON
- `ctx.ui.custom` 仅在 TUI 可用; 命令先检查 `ctx.mode === "tui"`，RPC/print 路径返回明确结果
- TUI 状态变更持久化后立即更新组件值并触发重绘

### 日志与安全

- 日志失败不抛; 文件大小有上限并轮转; 测试默认不写生产日志
- 日志不写 token、Authorization、cookie、password 或 secret; 结构化 dump 先脱敏，URL 去 query
- Debug 关闭时仍记录错误和非预期行为; Debug 仅增加诊断细节

### 测试与交付

- 单元与集成测试通过依赖注入隔离网络、文件系统和凭据; 不读写生产目录
- 真实 Pi E2E 使用临时目录和经济模型; 先从 `pi --list-models` 选择 free / mini / nano / flash
- E2E 不以手改 fixture 或生产文件掩盖缺陷; 结束后清理临时 Session、日志和测试数据
- 提交前运行项目统一验证命令 (`just verify`); 项目使用 changesets 时，用户可见行为变更必须带 changeset
