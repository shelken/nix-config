---
name: doc-user-guide
description: 当用户需要写用户指南时阅读
disable-model-invocation: true
---

# doc-user-guide

## 作用

限定如何写用户指南

## 规则

- 用户指南应该简洁明了，易于理解
- 默认放在项目`docs/user-guide`下, 自带一个README.md用来索引, 存放一个表格, 记录所有当前目录下的文档, 一列文件名和路径, 一列简要注释
- 使用 `00-<slug>.md` 的格式进行命名; 一般00用来写quickstart, 指引用户
- 每个编号对应一个特定功能模块, 根据项目来自动识别
- 根据代码实现的功能写功能描述(不要繁杂,核心功能)
- 有展示核心配置示例, 和配置的表格(描述默认值和作用)
- 项目根 `README` 中引导用户查看(使用文件链接跳到`docs/user-guide/README.md`)
