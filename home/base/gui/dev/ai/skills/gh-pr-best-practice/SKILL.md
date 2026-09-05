---
name: gh-pr-best-practice
description: 当提交PR时阅读该技能
---

## Rules

- 如果涉及 其他公开(非本人) 仓库, 阅读`gh-open-policy`
- 提交前必须完整阅读目标仓库的 `CONTRIBUTING.md` 和 `.github/{PULL_REQUEST_TEMPLATE}.md`，按其要求的格式填写 PR title、body、commit message
- PR title 的 `scope` 必须参考该仓库已合并 PR 的惯例（`gh pr list --state merged` 查看），不要自造
- **git提交message禁止自行添加 `Co-Authored-By` trailer,也不要自行清除任何 `Co-Authored-By`**
- 基于 upstream 的干净基点建分支，不要在 fork main 上累积多个 commit 后再提 PR；多个修复 commit 压缩为一个再提交
- 推送前确认 PR 关联的上游 issue 编号正确（`Fixes #xxx`），且 issue 确实是同一根因
- 禁止直接修改commit历史, 不要amend, 清晰地在pr中展示每个历史变更
