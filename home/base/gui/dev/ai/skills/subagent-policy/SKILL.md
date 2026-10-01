---
name: subagent-policy
description: 发起、审查或规划子代理工作时(位于pi中)阅读该技能
---

# 子代理

基本规范适用于所有环境；非 Workflow 场景使用下述流程，Workflow 遵循独立编排逻辑

## 基本规范

- 没有明确理由时，保留子代理已有的 model 和 thinking 配置
- 不重复派发子代理处理小修改；只有较大问题或修改才重新审查
- 子代理不再派生子代理；受主代理明确委托执行流程测试或审查协调时，可按主代理身份行事
- 大量变更或多轮任务之后，适合使用 reviewer
- 派发时提供相关 Issue、背景、前因后果和用户完整意图；细节用查询指针提供，如 Issue 链接和重要文件路径

## `spawn-subagent` 环境限制

- `spawn-subagent` 仅支持 Pi 和 Herdr；非 Herdr 环境（包括 Kitty）会停止并报告，不做降级。Oh My Pi（omp）使用原生子代理控制
- 复审时用 intercom 与子代理交流；主代理有不同意见时可直接讨论，直到达成共识

## `spawn-subagent` 流程

**第一步：`spawn-subagent -h` 看帮助**。命令语法、单发/batch/resume/close 用法、失败分类、manifest 格式、profile 机制、退出码，全部以 -h 为准，不在此记录（可能过时）。

然后按 SOP：

1. `spawn-subagent list` 查看可用 profile 与生效配置
2. 派发成功后主代理**立即结束当前回合**（不再调用任何工具、不 sleep、不轮询）：子代理结论经 intercom 自动注入并唤醒主代理继续处理，这是唯一可靠姿势
3. 结论收齐后按需 `spawn-subagent close <pane-id>` 清理；子代理 blocked / failed 时 pane 保留供用户检查，不自动关闭

### 等待模式为何是唯一姿势

herdr 对未聚焦 pane 的 agent 全程仅报 idle（无 working/done 区分），阻塞等待无可靠信号，等待统一由 intercom 注入完成
