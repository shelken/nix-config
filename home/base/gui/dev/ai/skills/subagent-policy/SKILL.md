---
name: subagent-policy
description: 子代理的派发、审查与规划规范，含 `spawn-subagent` 流程。在 pi 中发起、审查或规划子代理工作时使用。
---

# 子代理

基本规范适用于所有环境。非 Workflow 场景使用下述流程；Workflow 遵循独立编排逻辑。

## 基本规范

- 没有明确理由时，保留子代理已有的 model 和 thinking 配置
- 小修改不重复派发子代理；只有较大问题或修改才重新审查
- 子代理不再派生子代理；受主代理明确委托执行流程测试或审查协调时，可按主代理身份行事
- 大量变更或多轮任务之后，适合使用 reviewer
- 复审时用 intercom 与子代理交流；主代理有不同意见时可直接讨论，直到达成共识
- 派发时提供相关 Issue、背景、前因后果和用户完整意图；细节用查询指针提供，如 Issue 链接和重要文件路径

## `spawn-subagent` 环境限制

- `spawn-subagent` 支持 Pi 在 Herdr 或 Kitty 中运行（同时存在时 Herdr 优先）；其他终端会停止并报告，不做降级。Oh My Pi（omp）使用原生子代理控制
- Kitty 要求 `allow_remote_control=socket-only` 与 `listen_on`（已由 nix-config 配置），且当前 tab 布局为 splits；pane-id 为 kitty 窗口 ID
- `scout` 在 pi 中只靠提示词约束输出结构（omp 里由 output schema 强制）；需要稳定的 Summary/Files/Architecture 三段式时，在派发任务里明确要求格式

## `spawn-subagent` 流程

**第一步：运行 `spawn-subagent -h`**。命令语法、单发/batch/resume/close 用法、失败分类、manifest 格式、profile 机制、退出码，全部以 -h 为准，不在此记录（可能过时）。

然后按 SOP：

1. `spawn-subagent list` 查看可用 profile 与生效配置
2. 派发成功后主代理**立即结束当前回合**（不再调用任何工具、不 sleep、不轮询）：子代理结论经 intercom 自动注入并唤醒主代理继续处理。这是唯一可靠做法：herdr 对未聚焦 pane 的 agent 全程仅报 idle（无 working/done 区分），kitty 窗口更无任何完成信号，阻塞等待无可靠信号
3. 结论收齐后按需 `spawn-subagent close <pane-id>` 清理
   - 任务执行中子代理 blocked / failed：pane 保留供用户检查，不自动关闭
   - 派发阶段健康门失败：脚本自动关闭该 pane，不残留（详见 `-h`）
