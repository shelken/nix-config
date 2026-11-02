---
name: gh-pr-best-practice
description: PR 提交规范：目标仓库与模板、分支与 commit 历史、正文与截图、图片上传、归档。创建、更新或归档 PR 时使用。
---

## 准备与目标仓库

- 提交前确认目标目录对应的默认仓库，避免提交到错误的 repo
- 涉及他人的公开仓库时，先阅读 `gh-open-policy`
- 完整阅读目标仓库的 `CONTRIBUTING.md` 和 PR 模板（`.github/PULL_REQUEST_TEMPLATE.md` 或 `.github/PULL_REQUEST_TEMPLATE/` 目录），按要求填写 PR title、body 和 commit message
- PR title 的 scope 沿用仓库已合并 PR 的惯例，用 `gh pr list --state merged` 查看，不自行创造

## 分支与提交历史

- 从 upstream 的干净基点建立分支，不在 fork main 上累积多个 commit 后再提 PR；多个修复 commit 压缩为一个后提交
- 单个 PR 的 base 是默认分支；紧耦合改动合成一个分支、一个 PR
- 有依赖关系的多个改动用 GitHub 原生 stacked PRs：`gh stack` 建栈，栈底 PR 的 base 是默认分支，整条栈落到默认分支；建栈、提交、rebase、合并的完整流程与踩过的坑见 [references/gh-stack.md](references/gh-stack.md)
- 栈内保持线性历史靠 `gh stack rebase` 加 `gh stack push`（`--force-with-lease`），这是「不改写历史」的例外
- 手工堆栈（PR 的 base 指向另一个 feature 分支）须在合并前逐个执行 `gh pr edit <n> --base <默认分支>`：合并进非默认分支的 PR 不会关闭 `Fixes` 引用的 Issue；GitHub 只在合并后删除 head 分支时自动重定向依赖 PR 的 base，`gh pr merge --delete-branch` 时并不可靠
- 一般情况不直接修改 commit 历史，不 amend，让每个历史变更在 PR 中清晰可见
- 不自行添加或清除 commit message 中的 `Co-Authored-By` trailer

## 正文与验证

- 阅读 `pr`，在 body 中以通俗易懂的方式展示关键变更
- UI 变更在 PR 中提供 1 到 3 张有效验证截图，尺寸为 1920×1080；浏览器场景阅读 `agent-browser`，桌面应用阅读 `computer-use-best-practice`
- 推送前核对 `Fixes #xxx` 引用的上游 Issue，确认编号正确且根因相同

## 上传图片

- 截图通过 `gh` 上传，先排除隐私信息；图片不进入 commit 或仓库，不为单张图片创建 `docs/images` 等目录
- gh ≥ v2.99 使用 `gh pr edit <N> --body-file <f> --attach "<路径>#alt"`；body 中同路径引用自动改写为全局可渲染的 `user-attachments` URL
- `--attach` 按目标仓库写权限校验，他人仓库可能返回 404；网页端 cookie 流只要求评论权限。无写权限时，先在 fork PR 中 attach 获取 URL，再写入上游 body

## 归档

- 仅在用户明确要求时归档 PR；归档后非管理员访问该 PR 会返回 404

  ```bash
  gh api graphql -f query='mutation{archivePullRequest(input:{pullRequestId:"'$(gh pr view <N> --json id -q .id)'"}){pullRequest{number state}}}'
  ```
