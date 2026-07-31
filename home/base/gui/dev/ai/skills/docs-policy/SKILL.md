---
name: docs-policy
description: 编写、修改项目文档，或需要统一文档约定时阅读该技能
---

# 文档

- 当用户说保存plans时,通常将计划保存在`~/Code/docs/{project-name}/plans`下,名称格式`y-M-D-slug.md`
- 当项目没有对应 GitHub 仓库且需要保存 spec 时，保存到 `~/Code/docs/{project-name}/specs`，名称格式为 `y-M-D-slug.md`
- 文档记录问题(踩坑点和解决方式)时, 永远使用这个格式: `简短的说问题 -> 简短的目前最佳解决方式`
- 禁止在项目的任何文档中出现绝对路径, 使用slug指代前缀
- 无须列表的末尾永远不写标点符号; 文档中一段话的末尾默认不写句号
