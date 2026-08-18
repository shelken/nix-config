---
name: workflow-best-practice
description: 当 编排动态工作流/dynamic workflow 前阅读该技能
---

## Rules

- 合理使用模型, explore/探索/调研 类型的任务使用small; 普通任务使用medium; 审查/review 任务可以medium/big(看情况); 最后把关时(如果需要)可以big/medium
- 每个阶段默认值为 1-4 个 agent 并行, 一个阶段无法完成就拆, 一个阶段最大尽量不超过4个agent
- 必须在prompt中告知所有agent 重要的代码文件位置/用户反馈/背景信息/url链接/文件链接 等 以及对应的任务
