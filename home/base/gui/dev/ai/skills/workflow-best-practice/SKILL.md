---
name: workflow-best-practice
description: 当 编排动态工作流/dynamic workflow 前阅读该技能
---

## 编排原则

- 按任务选择模型：探索与调研用 small，普通任务用 medium，审查和最终把关按需用 medium 或 big；用户明确指定时遵循用户指令
- 每个阶段默认并行 1 到 4 个 agent，尽量不超过 4 个；单阶段无法完成时拆分阶段
- 每个 agent 的 prompt 必须包含对应任务及必要背景：重要代码位置、用户反馈、上下文、URL 和文件链接
