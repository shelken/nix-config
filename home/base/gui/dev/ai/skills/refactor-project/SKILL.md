---
name: refactor-project
description: Use when 用户要求全项目重构、跨文件重复消除、一致性标准化，或调用 /refactor-project。
---

# Refactor Project

执行全项目范围重构。不要依赖预置 agent 文件；请按 `references/code-simplifier.md`
动态创建（或在主线程按同规格执行）。

## 执行步骤

1. 预检查

- 运行 `git rev-parse --is-inside-work-tree`
- 不在 git 工作区时直接提示并退出
- 记录基线提交：`git rev-parse --short HEAD`

2. 发现范围

- 按 `references/scope-analysis.md` 生成范围摘要
- 展示摘要后自动继续

3. 执行重构

- 读取
  `references/code-simplifier.md`，并将该文件正文注入为子 agent 提示词（不同客户端/模型自行按本地机制加载）
- 客户端支持子 agent 时：按规格创建 `code-simplifier` 并执行
- 不支持子 agent 时：主线程按同规格执行

4. 输出

- 按 `references/output-requirements.md` 结构输出

## 要求

- 展示范围后立即执行，不等待二次确认
- 处理整个项目代码范围
- 优先跨文件重复消除和模式统一
- 保持行为与公共接口不变（除非用户明确要求改行为）
