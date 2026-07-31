---
name: pi-extension-best-practice
description: 写或审查 pi 插件(pi extension) 时使用
---

# pi 插件最佳实践

pi 插件在 pi 事件 (`session_start` / `model_select` / `agent_end` 等) 中的行为遵守一组通用约束: **非阻塞、模型门闩、跨进程锁**. 各 provider 以此为骨架, 再叠加自身网络.

## 何时用

- 编写或修改任何 pi 插件的 `session_start` / `model_select` 处理
- 审查插件是否在多 pi 并发启动时重复打网络
- 设计 provider 的签到 / 额度刷新等后台任务

## 拆分

各主题拆到同目录下独立文件, 按需加载:

- [session-start 规范](./session-start.md) — `session_start` 与 `model_select` 的通用契约 (`activate` 函数、三层门闩、锁). 写/审 session_start 时加载.

## 原则速查

- 网络一律 `p().catch(log)`, 绝不 `await` 阻塞事件循环
- 当前模型非本 provider 管辖 → 跳过一切网络 (模型列表属 factory, 豁免)
- 有副作用的网络 (签到类: 写远端/写账号状态) 用跨进程文件锁; 只读 GET 不加锁
- 账号级后台任务额外加 `ctx.hasUI` 门闩, 防 pi-subagent 同进程重复触发
- `session_start` 与 `model_select` 共用同一个 `activate(ctx, isMine)` 入口, 行为一致
