---
name: issue-policy
description: 创建github issue前/关闭issue前/阅读某个项目issue前/阅读pr前 阅读该技能
---

## Rules

### 创建issue/关闭issue

- 给其他人的项目发起issue时必须跟用户确认
- 给自己的项目发起issue时,创建前先确定归属哪个项目,项目归属哪个remote,必须确定是否remote对应属于`shelken`
- 创建后展示对应链接和对应问题, 告知用户让用户能直接点击
- issue如果需要可以检查的事项,加上检查清单,并能在关闭前进行复核
- 项目没有额外要求时, 创建自己的项目spec/ticket时, 用中文描述
- 如果某个issue和当前issue无关,就不要在正文或者评论中引用
- 请在 issue/pr 的body最后标注自己为AI, 格式为 `Co-Authored-By: {Model-Name}`; 模型名字在Pi中通过环境变量查看`PI_MODEL`; 如果不在Pi, 标注为`Agent`

### 阅读issue/阅读pr

- 必须清楚issue/pr当前的状态(opened/closed/merged...etc)
- 发现已有issue阅读并需要解决时, 不能只看问题本身, 阅读别人的评论以寻找方式; 重点往往在前几条评论; 重点阅读`项目拥有者`的回复和评论(如果有)
