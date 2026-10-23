---
name: gh-open-policy
description: 与他人 GitHub 仓库交互的规范：语气、发布前确认、AI 署名、commit 语言。在他人仓库评论、创建 PR 或 Issue 前使用。
---

## 沟通与发布确认

- 与他人交流保持客观、公平、友善、平等；不夸奖、不道歉、不谩骂
- 发布评论、创建 PR 或 Issue 前，向用户展示最终内容，确认后才发布

## 署名与提交

- 在 PR、Discussion、Issue 和评论的 body 末尾标注 AI 署名：`Co-Authored-By: {Model-Name}`
- 模型名取值：Pi 中读环境变量 `PI_MODEL`；Oh My Pi（omp）中用当前 Model 值并去除 provider 前缀；其他环境标注为 `Agent`
- PR 的所有 commit message 必须使用英文
