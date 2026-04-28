## 来源

https://github.com/hyperb1iss/hyperskills/tree/main/skills

## 翻译修正要求

- 目录结构保持一致：`README.md`、`SKILL-origin.md`、`SKILL.md`。
- `SKILL-origin.md` 保存原版英文内容，中文整理版以原文为准。
- `description` 保持纯英文。
- 保留用户已经处理过的删改内容，避免补回已移除段落。
- 生硬直译改成自然中文；难以准确翻译的术语保留英文。
- 表格、引用示例、任务模板、计划模板里的可读文本尽量中文化。
- 统一使用普通英文双引号。
- Markdown 标题优先使用原版英文标题；涉及本地化强制替换时，以本地化约定为准。
- `What This Skill is NOT` 整段使用原文；涉及本地化强制替换时，以本地化约定为准。
- 保留命令、工具名，以及必要的英文术语。
- 所有`hyperskills:<?>` 换成 `hyperskills-<?>`；skill name 统一写为
  `hyperskills-<?>`；对应的目录也保持和 name 一致
- 当需要变更时，先了解上次提交的时候和翻译和原版差了哪些内容，以确定本次变更不把原先删除的弄回来
- 替换： `cross-model-review` -> subagent-review
- 使用 Hindsight 替代上游文档中的 Sibyl。
- 不把 Sibyl 的 task、entity、category、explore、relationship、stale
  update 等概念硬映射到 Hindsight。

## How the Skills Work Together

The skills form a workflow pipeline. Each one handles a phase of the development lifecycle and hands
off to the next:

```
brainstorm ──→ research ──→ plan ──→ implement ──→ subagent-review
    │              │           │                            │
    │              │           │                            └──→ dream
    │              │           │
    │              │           └──→ orchestrate
    │              └──→
    └──→ Any skill can loop back when new questions emerge
```

**Typical flows:**

| Scenario              | Flow                                                             |
| --------------------- | ---------------------------------------------------------------- |
| New feature           | `brainstorm` → `plan` → `implement` → subagent-review            |
| Greenfield project    | `brainstorm` → `research` → `plan` → `orchestrate` → `implement` |
| Bug fix               | `implement` (straight to it — scale selection handles this)      |
| Architecture decision | `brainstorm` → `research` → decide                               |
| Large refactor        | `plan` → `orchestrate` → `implement` → subagent-review           |
| Memory maintenance    | `dream` → Hindsight knowledge consolidation                      |

You don't need to follow the full pipeline. Each skill has built-in scale selection — a typo fix
doesn't need brainstorming, and a clear bug doesn't need research. Start wherever makes sense.
