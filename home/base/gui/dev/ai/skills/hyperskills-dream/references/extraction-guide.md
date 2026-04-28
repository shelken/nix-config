# Dream Extraction Guide

本指南用于 `hyperskills-dream`。目标是从 Pi、Claude
Code、Codex 会话中提取可复用知识，并用中文写入 Hindsight。

Pi 是主要 client。处理顺序：Pi sessions → Claude Code sessions → Codex sessions。

## What to Extract vs Skip

### High-Value Extractions

| Signal                    | Hindsight 内容类型 | Example                                                                  |
| ------------------------- | ------------------ | ------------------------------------------------------------------------ |
| 用户修正 assistant 的方法 | 反模式 / 规则      | "不要用 `uv pip` 管项目依赖；项目依赖用 `uv add`"                        |
| 带取舍的技术决策          | 决策               | "选择 Temporal，因为 workflow 可见性比实现简洁更重要"                    |
| 非显而易见的调试发现      | 模式 / 反模式      | "FalkorDB WRONGTYPE 常见于 key schema 变化；开发环境可清理旧 key 后复测" |
| 可复用代码模式            | 模式               | "长时间 Temporal activity 用 heartbeat future 维持可见性"                |
| 已确认的强约束            | 规则               | "不要提交 .env；项目使用 SOPS 管 secrets"                                |
| 延后处理的问题            | 待定问题           | "Hindsight 项目 bank 是否需要按 repo 细分，仍需观察检索质量"             |
| 新工具 / 新库采用         | 决策               | "采用 better-auth 替换 next-auth，因为多租户支持更贴近需求"              |
| 性能发现                  | 模式               | "批量写入比逐条 CLI 调用更适合大量记忆整理"                              |
| 配置细节                  | 反模式 / 规则      | "moon workspace 即使为空也需要 `.moon/toolchains.yml`"                   |

### Skip These (Low/No Value)

| Signal                   | Why Skip                             |
| ------------------------ | ------------------------------------ |
| 简单问答（"X 是什么？"） | 文档可查，迁移价值低                 |
| 文件读取、目录浏览       | 临时导航信息                         |
| 日常 git 操作            | git history 已记录                   |
| 拼写修正                 | 没有模式价值                         |
| 模板代码生成             | 代码本身是产物                       |
| 未找到原因的调试         | 缺少可复用洞察                       |
| 只阅读代码的会话         | 除非发现了非显而易见的约束或设计原因 |

---

## Quality Bar for Extractions

### Bad Extractions (Don't Write These)

```text
"修好了 auth bug"
```

缺少问题、原因、适用场景。

```text
"前端用了 React"
```

这是项目事实，可从代码或依赖文件获取。

```text
"更新了 README"
```

git commit 已记录，缺少知识价值。

### Good Extractions

```text
"反模式：JWT refresh token 在 Redis TTL 早于 token 过期时会静默失败。原因：token service 捕获 WRONGTYPE 后吞掉错误。有效做法：SET 前检查 key 类型；类型不匹配时重新生成 token。适用范围：使用 Redis 保存 JWT 且 TTL 独立配置的服务。"
```

```text
"模式：Temporal activity future 需要周期性 heartbeat。做法：用 select loop 包装 activity future，每 30 秒发送 heartbeat。缺少 heartbeat 时，Temporal 会在 heartbeat timeout 后标记 activity 失败。"
```

```text
"决策：选择 FalkorDB 而非 Neo4j。理由：Redis-compatible protocol 贴合现有基础设施，内置 vector similarity search，小规模图查询更快。取舍：生态成熟度较低，社区资料较少。"
```

### The Transfer Test

写入前判断：这条内容换到另一个会话或另一个项目里是否仍有帮助？

| Answer | Action                     |
| ------ | -------------------------- |
| Yes    | 写入 Hindsight             |
| Maybe  | 写入时限定上下文和适用范围 |
| No     | 跳过                       |

---

## Hindsight Memory Shapes

Hindsight 使用自然语言记忆。不要把内容拆成伪结构化知识字段。用稳定中文模板让 recall 和 rerank 更容易命中。

### Decision

```bash
hindsight-embed memory retain project-[name] "决策：[决策内容]。理由：[理由]。曾考虑方案：[候选项]。取舍：[取舍]。上下文：[项目/功能]。日期：[date]。"
```

适合：架构选择、库选型、API 形状、部署策略、数据模型。

### Pattern

```bash
hindsight-embed memory retain project-[name] "模式：[名称]。描述：[描述]。适用场景：[上下文]。示例：[简短代码或命令]。发现项目：[项目]。日期：[date]。"
```

适合：有效做法、可复用调试路径、稳定工程习惯。

### Anti-Pattern

```bash
hindsight-embed memory retain project-[name] "反模式：[错误做法]。错误尝试：[尝试内容]。失败原因：[原因]。有效做法：[方案]。适用范围：[范围]。"
```

适合：用户修正、工具误用、失败的迁移策略、错误假设。

### Rule

```bash
hindsight-embed memory retain project-[name] "规则：[规则内容]。原因：[原因]。适用范围：[范围]。违反后果：[后果]。发现日期：[date]。"
```

适合：强约束、安全要求、项目约定、不可违反的操作规范。

### Open Question

```bash
hindsight-embed memory retain project-[name] "待定问题：[问题]。上下文：[触发原因]。已考虑选项：[候选项]。当前阻碍：[信息缺口]。下一次判断依据：[依据]。"
```

适合：延后决策、方案冲突、需要真实数据验证的问题。

---

## Deduplication Strategy

### Before Writing to Hindsight

1. 查项目 bank：

   ```bash
   hindsight-embed memory recall project-[name] "[关键词]"
   ```

2. 查默认 bank：

   ```bash
   hindsight-embed memory recall default "[关键词]"
   ```

3. 按结果处理：

   | Recall Result      | Action                             |
   | ------------------ | ---------------------------------- |
   | 无相似内容         | 写入新中文记忆                     |
   | 同主题，旧内容较粗 | 写入更精确的新事实，并说明差异     |
   | 同主题，内容相同   | 跳过，在 dream report 记为重复     |
   | 同主题，内容冲突   | 写入冲突点、适用上下文、待确认问题 |
   | 相关但主题不同     | 写入新记忆，并保留清晰上下文       |

### Within a Single Dream Cycle

多个会话可能包含同一洞察。写入 Hindsight 前先在提取集合里去重：

1. 按主题关键词分组
2. 合并重复内容，保留信息最完整的一条
3. 在记忆里写清来源项目或会话范围
4. 对低置信内容标注"需要后续确认"

---

## Source Conventions

Hindsight 没有独立 tag 字段；把来源和范围写进中文内容本身。

### Recommended Fields in Memory Text

| Field  | Example                     |
| ------ | --------------------------- |
| 项目   | `项目：nix-config`          |
| 来源   | `来源：Pi session`          |
| 范围   | `适用范围：Nix flakes 配置` |
| 置信度 | `置信度：高`                |
| 日期   | `日期：2026-04-28`          |

### Source Labels

- `来源：Pi session` — 主来源
- `来源：Claude Code session` — 辅助来源
- `来源：Codex session` — 辅助来源
- `来源：subagent-review` — 独立审查发现

### Bank Selection

| Knowledge Scope    | Bank             |
| ------------------ | ---------------- |
| 当前项目特有       | `project-[name]` |
| 跨项目通用         | `default`        |
| 用户偏好和长期习惯 | `default`        |
| 临时任务状态       | 通常不写入       |

---

## Examples: Full Extraction from a Conversation

### Input: Pi Session Excerpt

```text
User: "我都说了，Pi 是主要 client，dream 也需要。"
Assistant: [只更新主 SKILL.md，漏掉 references]
User: "重新引入的文件你也不做任何翻译，也不做任何修改。"
```

### Extractions

**1. Rule:**

```bash
hindsight-embed memory retain project-nix-config "规则：hyperskills-dream 的主来源必须是 Pi session，相关 references 也要体现 Pi 优先级。原因：当前工作流以 Pi + hindsight-pi 为主，Claude Code 和 Codex 只是辅助来源。来源：Pi session。日期：2026-04-28。"
```

**2. Anti-Pattern:**

```bash
hindsight-embed memory retain project-nix-config "反模式：补回上游 references 后只复制英文原文。失败原因：任务目标是本地化与 Hindsight/Pi 适配，references 也属于用户可读文档。有效做法：补回文件后同步翻译，并改为 Hindsight 自然语言记忆模型。来源：Pi session。日期：2026-04-28。"
```

**3. Decision:**

```bash
hindsight-embed memory retain project-nix-config "决策：hyperskills references 文件保留上游结构，但内容按本地 Hindsight/Pi 约定改写。理由：references 是 skill 使用的一部分，保留结构方便对照，语义必须匹配本地工作流。来源：Pi session。日期：2026-04-28。"
```

---

## Pi-First Extraction Checklist

1. 先查 `~/.pi/agent/sessions/`，再查 Claude Code 和 Codex。
2. 优先阅读当前项目目录对应的 Pi session。
3. 重点关注用户修正、工具错误、compaction summary、modified files。
4. 写入 Hindsight 前先 recall。
5. `retain` 内容使用中文。
6. 不把上游结构化知识模型迁移成伪 Hindsight 字段。
7. 只记录可迁移知识，跳过普通操作流水。
