---
description: 清理 worktrees
argument-hint: "[特定项目]"
---

用 `git-scan` 清理 worktrees（判定与安全规则以 `git-scan` 为准）

- 目标：`${@:-~/Code/worktrees}`；传入项目名时解析为对应主仓库路径（如 `~/Code/active/<项目>`）
- 预览：运行 `git-scan -w --fetch <目标>`，向用户展示清单并确认（用户已明确要求直接清理则跳过）
- 清理：运行 `git-scan --clean --fetch <目标>`，仅清理「可清理」项，不因远端 PR 状态绕过本地判定强删
- 汇报：列出已删 worktree 与本地分支数量，以及保留项与原因
