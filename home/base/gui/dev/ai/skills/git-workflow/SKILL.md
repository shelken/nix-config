---
name: git-workflow
description: Git 提交、GitHub 日常操作或提交前文档检查时阅读该技能
---

# Git

## 提交前检查

- 检查关键文档（AGENTS.md、README.md、CHANGELOG.md 等），修正过时或错误的内容；需要新增内容时，先向用户说明并取得同意
- 提交内容必须去除隐私信息，包括真实手机号、地址、身份、生产数据等；测试数据也使用非真实数据
- 修复 bug 时必须先自行验证修复成功，验证通过前不提交

## 提交方式

- 环境中有 eval 工具时，仍使用 bash 执行 Git 提交
- 自己的项目默认使用中文提交消息，按 remote 是否归属于 `shelken` 判断；其他项目使用英文，项目特别约定优先
- 提交消息必须使用 `HEREDOC`，先说明原因，再总结变更；沿用仓库现有格式，无既有格式时使用 Conventional Commits
