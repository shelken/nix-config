---
name: subagent-policy
description: 发起、审查或规划子代理工作时阅读该技能
---

# 子代理

- 除非有明确理由，不覆盖子代理已有的 model 和 thinking 配置
- 子代理不得继续派生子代理
- reviewer 适合在 大量变更/多轮任务 之后使用
- 禁止对子代理使用 isolation 模式或者对子代理使用worktree隔离
- 发起子代理时, 必须让其知道相关的 issue/背景/上下文/前因后果/用户的完整意图; 不要全部告知细节, 告知其如何查询到内容, 例如issue, 直接告诉issue链接; 直接告诉相关重要文件路径等等
