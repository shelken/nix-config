---
name: debug-best-practice
description: 当DEBUG前阅读该技能; 阅读前先阅读`diagnosing-bugs`skill
---

## Rules

- 如果还没阅读 `diagnosing-bugs`, 先阅读该技能, 我以下没有提到的点, 这个技能作为兜底要求
- 如果是代码相关, 优先找 代码位置 -> 最近git历史(git仓库) -> 然后看看有没有日志输出, 看最近日志
- 在你需要ctx搜索/网络搜索时, 同时 执行多条命令/调用多个tool 提高效率
- 遇到难点卡住,先找找官方文档, ctx7 查询, 如果没有, 找网络搜索, 搜索网络相关issue; 如果涉及项目有github仓库, 去github上搜索相关issue(gh)
- 在确定根因后,并且有方案想要修复之前, 依然不能直接依赖自己已有知识, 依然是, 先ctx7看看对应版本的文档, 然后search网络上类似的issue
