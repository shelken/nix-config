---
name: gh-pr-best-practice
description: 当提交PR时阅读该技能
---

## 准备与目标仓库

- 提交前确认目标目录对应的默认仓库，避免提交到错误的 repo
- 涉及他人的公开仓库时，先阅读 `gh-open-policy`
- 完整阅读目标仓库的 `CONTRIBUTING.md` 和 `.github/{PULL_REQUEST_TEMPLATE}.md`，按要求填写 PR title、body 和 commit message
- PR title 的 scope 沿用仓库已合并 PR 的惯例，用 `gh pr list --state merged` 查看，不自行创造

## 分支与提交历史

- 从 upstream 的干净基点建立分支，不在 fork main 上累积多个 commit 后再提 PR；多个修复 commit 压缩为一个后提交
- PR base 必须是默认分支，不通过 feature 分支互相 merge 建立堆栈；紧耦合改动合成一个分支、一个 PR
- 已有堆栈须在合并前逐个执行 `gh pr edit <n> --base <默认分支>`；否则 GitHub 不会自动重定向 base 或关闭 Issue
- 不直接修改 commit 历史，不 amend，在 PR 中清楚展示每个历史变更
- 不自行添加或清除 commit message 中的 `Co-Authored-By` trailer

## 正文与验证

- 阅读 `pr`，在 body 中以通俗易懂的方式展示关键变更
- UI 变更在 PR 中提供 1 到 3 张有效验证截图，尺寸为 1920×1080；浏览器场景阅读 `browser-best-practice`，桌面应用阅读 `computer-use-best-practice`
- 推送前核对 `Fixes #xxx` 引用的上游 Issue，确认编号正确且根因相同

## 上传图片

- 截图通过 `gh` 上传，先排除隐私信息；图片不进入 commit 或仓库，不为单张图片创建 `docs/images` 等目录
- gh ≥ v2.99 使用 `gh pr edit <N> --body-file <f> --attach "<路径>#alt"`；body 中同路径引用自动改写为全局可渲染的 `user-attachments` URL
- `--attach` 按目标仓库写权限校验，他人仓库可能返回 404；网页端 cookie 流只要求评论权限。无写权限时，先在 fork PR attach 获取 URL，再写入上游 body

## 归档

- 仅在用户明确要求时归档 PR：`gh api graphql -f query='mutation{archivePullRequest(input:{pullRequestId:"'$(gh pr view <N> --json id -q .id)'"}){pullRequest{number state}}}'`；归档后非管理员访问该 PR 会返回 404
