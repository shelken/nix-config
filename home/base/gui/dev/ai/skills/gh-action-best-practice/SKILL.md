---
name: gh-action-best-practice
description: 当使用github action有关操作时阅读该技能
---

## Rules

- 观察action进度时, 禁止任何超长时间的等待, 必须先预估执行时间, 设定合理超时时间, 在超时之后立刻检查日志详情; 禁止长超时时间; fail-fast
- 使用 临时命令或者脚本时 用`轮询机制`进行探测状态, 也就是在探测到目标状态或确定检测到失败状态后返回结果;
- action中 PR 创建失败, 使用gh开启repo的权限
  ```bash
  gh api -X PUT repos/:owner/:repo/actions/permissions/workflow \
     -f default_workflow_permissions=read \
     -F can_approve_pull_request_reviews=true
  ```
