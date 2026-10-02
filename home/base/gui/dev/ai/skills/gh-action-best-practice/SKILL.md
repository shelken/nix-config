---
name: gh-action-best-practice
description: 当使用github action有关操作时, 编写action/workflow时 阅读该技能
---

## 运行状态与失败定位

- 观察 Action 进度时，先预估执行时间并设置合理的短超时；超时后立即检查日志，避免长时间等待，保持 fail-fast
- 临时命令或脚本使用轮询探测状态，达到目标状态或确定失败后立即返回结果

## 工作流权限

- Action 中创建 PR 失败时，使用 `gh` 开启仓库对应权限

  ```bash
  gh api -X PUT repos/:owner/:repo/actions/permissions/workflow \
     -f default_workflow_permissions=read \
     -F can_approve_pull_request_reviews=true
  ```

## 依赖与检查结果

- 确保所有 Action 的 Annotations 无警告；依赖和构建组件使用稳定、受支持的版本，不使用已废弃组件
