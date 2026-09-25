---
name: gh-pr-best-practice
description: 当提交PR时阅读该技能
---

## Rules

- 如果涉及 其他公开(非本人) 仓库, 阅读`gh-open-policy`
- 阅读`visual-pr`skill, 在`body`中使用合适的方式通俗易懂的展示关键变更内容
- 提交前必须完整阅读目标仓库的 `CONTRIBUTING.md` 和 `.github/{PULL_REQUEST_TEMPLATE}.md`，按其要求的格式填写 PR title、body、commit message
- PR title 的 `scope` 必须参考该仓库已合并 PR 的惯例（`gh pr list --state merged` 查看），不要自造
- **git提交message禁止自行添加 `Co-Authored-By` trailer,也不要自行清除任何 `Co-Authored-By`**
- 基于 upstream 的干净基点建分支，不要在 fork main 上累积多个 commit 后再提 PR；多个修复 commit 压缩为一个再提交
- **PR 的 base 必须是默认分支，禁止 feature 分支互相 merge 形成堆栈**（紧耦合改动合成一个分支一个 PR 直合默认分支；已有堆栈须在合并前逐个 `gh pr edit <n> --base <默认分支>` 改回，否则 GitHub 既不自动重定向 base 也不自动关 issue）
- 推送前确认 PR 关联的上游 issue 编号正确（`Fixes #xxx`），且 issue 确实是同一根因
- 归档 PR（仅用户明确要求时做）：`gh api graphql -f query='mutation{archivePullRequest(input:{pullRequestId:"'$(gh pr view <N> --json id -q .id)'"}){pullRequest{number state}}}'`，归档后非管理员访问该 PR 得 404
- 禁止直接修改commit历史, 不要amend, 清晰地在pr中展示每个历史变更
