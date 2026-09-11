---
name: pi-extension-best-practice
description: 编写或审查任何 pi 插件的 factory、事件、命令、配置、日志或测试时使用
---

# pi 插件最佳实践

所有 pi 插件遵守通用边界: 轻量 factory、生命周期安全、数据边界、隔离验证。Provider 再叠加模型门闩、网络和跨进程锁

## 何时用

- 创建或修改 pi 插件的 factory、事件处理器、命令或 TUI
- 设计插件配置、缓存、日志和时间字段
- 编写插件单元测试、契约测试、真实 Pi 在线冒烟或审查生命周期安全
- 开发或排查 Provider 激活与生命周期同步逻辑

## 参考文档

- [session-start 规范](./references/session-start.md): Provider 的 `session_start` / `model_select` / `turn_start` 契约 (`activate`、模型门闩、`hasUI`、跨进程锁), 编写或审查 Provider 激活逻辑时加载
- [e2e 契约测试规范](./references/e2e-testing.md): 插件对外暴露能力、CLI 黑盒发现与回归测试规范, 包含测试选跑矩阵、零外部依赖测试模板及验证门禁, 编写或重构插件测试时加载

## 通用原则

### Factory 与生命周期

- Factory 只做注册和内存初始化; 网络与同步重 IO 延迟到 `session_start` 或实际调用路径
- 优先复用 pi 内置 API、组件和转换函数; 只有现有能力无法表达协议或交互时才自建实现
- `ctx` / `ctx.ui` 属于当前生命周期; 跨事件异步链使用 fresh ctx, 展示层失败不得破坏主流程

### 配置、存储与时间

- 全局配置放 `{pi-agent-dir}/extensions/<name>/config.json`; 项目配置放 `.pi/extensions/<name>/config.json` 并覆盖全局
- 缓存放 `{pi-agent-dir}/cache/<name>/`; 日志放 `{pi-agent-dir}/logs/<name>.log`; 测试使用临时目录
- 配置读写只投影已知键, 更新时保留未知键; 凭据与业务缓存使用独立文件
- 时间存储与传输统一使用 UTC ISO 8601 (`Date.toISOString()`); 展示时按用户当前时区转换

### 命令与 TUI

- 有用户配置时提供 `/xxx config`, 避免要求用户手改 JSON
- `ctx.ui.custom` 仅在 TUI 可用; 命令先检查 `ctx.mode === "tui"`, RPC/print 路径返回明确结果
- TUI 状态变更持久化后立即更新组件值并触发重绘

### 日志与安全

- 日志失败不抛; 文件大小有上限并轮转; 测试默认不写生产日志
- 日志不写 token、Authorization、cookie、password 或 secret; 结构化 dump 先脱敏, URL 去 query
- Debug 关闭时仍记录错误和非预期行为; Debug 仅增加诊断细节

### 测试与交付

- 单元测试通过依赖注入隔离网络、文件系统和凭据, 专精内部算法、边界与状态转移, 隔离生产目录
- 契约测试（E2E）使用 `tests/contract.test.ts`, 仅通过真实 `pi` CLI 与公开 `ExtensionAPI` 断言标准 Schema、退出码与事件返回, 严禁断言内部私有函数或局部变量
- 修改内部逻辑仅执行对应单元测试; 增改 Provider、Command、Tool、Flag 等对外能力时, 必须在契约测试中补齐对应标识断言
- 真实 Pi 在线冒烟使用临时目录和经济模型, 优先从 `pi --list-models` 选取 free / mini / nano / flash
- 提交前运行项目统一验证命令 (`just verify`), 确保单元测试与契约测试全部绿灯; 项目使用 changesets 时, 用户可见行为变更必须带 changeset
