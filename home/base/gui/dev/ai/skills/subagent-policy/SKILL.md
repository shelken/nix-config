---
name: subagent-policy
description: 发起、审查或规划子代理工作时(位于pi中)阅读该技能
---

# 子代理

**该skill适用于非Workflow场景下,Workflow使用独立的编排逻辑**
**该skill适用于Pi和herdr环境下,如果当前环境位于oh-my-pi(omp)下,直接使用omp的subagent控制**

子代理由 `spawn-subagent` 脚本在 Herdr 窗格中启动（替代已禁用的 pi-subagents 插件），通过 `pi-intercom` 回传结论

## 环境限制

- 仅支持 Herdr；非 Herdr（含 Kitty）脚本会停止并报告，不做降级

## 流程

**第一步：`spawn-subagent -h` 看帮助**。命令语法、单发/batch/resume/close 用法、失败分类、manifest 格式、profile 机制、退出码，全部以 -h 为准，不在此记录（可能过时）。

然后按 SOP：

1. `spawn-subagent list` 查看可用 profile 与生效配置
2. 派发成功后主代理**立即结束当前回合**（不再调用任何工具、不 sleep、不轮询）：子代理结论经 intercom 自动注入并唤醒主代理继续处理，这是唯一可靠姿势
3. 结论收齐后按需 `spawn-subagent close <pane-id>` 清理；子代理 blocked / failed 时 pane 保留供用户检查，不自动关闭

### 等待模式为何是唯一姿势

herdr 对未聚焦 pane 的 agent 全程仅报 idle（无 working/done 区分），阻塞等待无可靠信号，等待统一由 intercom 注入完成

## 使用规则

- 除非有明确理由，不覆盖子代理已有的 model 和 thinking 配置
- 禁止多次重复派发子代理，例如修复几行代码后重新派发。**经济原则**：非大问题/大修改不重新审查
- 子代理不得继续派生子代理（例外：受主代理明确委托执行子代理流程测试/审查协调时，以主代理身份行事）
- reviewer 适合在大量变更/多轮任务之后使用
- 发起子代理时，必须让其知道相关 issue/背景/上下文/前因后果/用户的完整意图；不要全部告知细节，告知其如何查询，例如直接给 issue 链接、重要文件路径
- batch manifest 的顶层 `task` 承载所有 agent 共享的完整上下文；agent 对象的 `task` 只写差异化分工，脚本会将两者组合后派发
- 复审时可使用 intercom 与子代理进行交流; **主代理有任何审查方面的不同意见, 可直接与子代理辩论相关问题, 直到达成共识**
