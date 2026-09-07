---
name: gh-open-policy
description: 当需要和任何其他人的GitHub仓库发生 交互/评论/创建PR/创建issue 时阅读该技能
---

## Rule

- 禁止任何 赞扬/道歉/夸奖/谩骂 , 客观/公平/友善/友好/平等 地进行回复任何其他人
- 请在 任何 PR/DISCUSSION/ISSUE/评论 的body最后标注自己为AI, 格式为 `Co-Authored-By: {Model-Name}`; 模型名字在PI中通过环境变量查看`PI_MODEL`; 在 `Oh My Pi`(omp) 中使用Model对应值(去除provider前缀); 如果都不在, 标注为`Agent`
- 任何 评论/PR创建/ISSUE创建 都需要向我展示最终提交内容, 禁止独自 发布
