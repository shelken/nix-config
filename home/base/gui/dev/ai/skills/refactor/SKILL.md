---
name: refactor
description: Use when 用户要求重构指定文件/目录、简化复杂逻辑、清理死代码，或调用 /refactor。
---

# Refactor

按目标范围执行自动重构。不要依赖预置 agent 文件；请按 `references/code-simplifier.md`
动态创建（或在主线程按同规格执行）。

## 执行步骤

1. 预检查

- 运行 `git rev-parse --is-inside-work-tree`
- 规范化参数（保留引号路径）
- 空参数视为“最近改动模式”

2. 范围确定

- 按 `references/scope-determination.md` 生成最终文件列表
- 若无可处理文件：直接结束并说明原因

3. 执行重构

- 读取
  `references/code-simplifier.md`，并将该文件正文注入为子 agent 提示词（不同客户端/模型自行按本地机制加载）
- 客户端支持子 agent 时：按规格创建 `code-simplifier` 并执行
- 不支持子 agent 时：主线程按同规格执行

4. 输出

- 按 `references/output-requirements.md` 结构输出

## 要求

- 立即执行，不等待二次确认
- 语义匹配到多个文件时全部处理
- 保持行为与公共接口不变（除非用户明确要求改行为）
