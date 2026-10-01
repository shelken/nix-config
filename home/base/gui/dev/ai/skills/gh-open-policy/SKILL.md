---
name: gh-open-policy
description: 当需要和任何其他人的GitHub仓库发生 交互/评论/创建PR/创建issue 时阅读该技能
---

## 沟通与发布确认

- 与他人交流保持客观、公平、友善和平等，不使用赞扬、道歉、夸奖或谩骂
- 发布评论、创建 PR 或 Issue 前，向用户展示最终内容，未经确认不发布

## 署名与提交

- 在 PR、Discussion、Issue 和评论的 body 末尾标注 AI 署名：`Co-Authored-By: {Model-Name}`
- Pi 中从环境变量 `PI_MODEL` 获取模型名；Oh My Pi（omp）中使用当前 Model 值并去除 provider 前缀；其他环境标注为 `Agent`
- PR 的所有 commit message 必须使用英文
