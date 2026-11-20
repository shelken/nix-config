---
description: 保存任务状态并开启新的上下文窗口（Posthorse）
argument-hint: "[下一步]"
---
把当前任务状态写进新 notes：目标、已完成、下一步、关键决定与约束、接下来建议阅读的skills。
关联上个note(如果不是首个)
然后调用 new_context，handoff 写明下一步：${@:-继续当前任务}。
