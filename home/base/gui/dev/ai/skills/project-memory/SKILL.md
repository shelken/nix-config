---
name: project-memory
description: 管理项目长期知识。recall 召回历史决策、capture 沉淀已验证经验、mine 挖掘未沉淀候选、audit 检查知识是否过时或错位。mine 与 audit 仅用户显式触发，不自动运行。
---

# Project Memory

## 目标

把历史对话当作证据源，把项目文件当作唯一长期事实源。检索、验证和路由由本 Skill 协调；跨 Session 读写统一走本机 `project-memory` CLI。具体产物遵循项目约定或对应专用 Skill。

## 调用约定

CLI 源码在本机开发树，不走 npm/GitHub；首次安装见 [INSTALL.md](INSTALL.md)。定 `$PM_DIR` 后一律 `bun run --cwd "$PM_DIR" pm -- <cmd>`（已 link 到 PATH 可用 `project-memory <cmd>`）：

```sh
PM_DIR="${HOME}/Code/active/project-memory"
test -d "$PM_DIR" || { echo "bad PM_DIR: $PM_DIR — 见 INSTALL.md" >&2; exit 1; }
test -f "$PM_DIR/package.json" || { echo "bad PM_DIR contents: $PM_DIR" >&2; exit 1; }
bun run --cwd "$PM_DIR" pm -- status   # 默认 text；程序用 status --format json
```

任何跨 Session 内容只能通过本机 CLI 读取。**禁止**直接读 Session JSONL，也禁止在业务项目 cwd 下拼相对路径脚本。各命令完整 flag 见 `<cmd> --help`。

## 核心原则

- 当用户单纯调用该技能时, 没有任何其他指示时, 默认检查本轮对话有哪些值得沉淀的经验,教训;如果有,向用户反馈是否记录哪些文档(agents/skill/尸检报告...等等)
- Session 只提供候选证据，不能直接成为项目事实
- 正式知识必须结合当前代码、Git、测试、运行结果或有效文档验证
- 能通过代码、类型、schema、测试、lint、CI 或脚本保证的约束，优先做成可执行约束
- 写入前先检查现有实现、规则、作用域和重复内容，优先更新、移动或删除原内容
- Session 路径、Entry ID 和对话片段只出现在运行报告中，不写入 Git
- 不建立独立的项目事实库；本地索引和审阅状态只是可丢弃辅助状态，不是项目事实源

### AGENTS.md

写作格式与约束读取 `doc-agent-file`（SSOT）。直接修改 `AGENTS.md` 永远只能提醒与建议。

### Skill

- 必须是项目强相关
- 写 skill 前先读取 `writing-great-skills`，缺失时提醒且不做记录
- 只记录可复用流程，不记录单次错误；踩坑点只有当以后会重复且重要才记录
- 语言精简凝练，模仿当前项目已有 skill 风格

### Postmortem

写尸检前先读取 `postmortem`，缺失时提醒且不做记录。小修小补不记录；重点记录重大错误、重复错误、高影响事故。用户未主动要求时，只有影响范围明显较大时才建议记录。

## 模式选择

| 模式 | 用途 | 默认写入权限 |
|---|---|---|
| `recall` | 回忆当前或历史对话，回答过去如何决策或处理 | 只读 |
| `capture` | 提炼当前任务中已验证的长期知识 | 证据和目标明确时可写 |
| `mine` | 分批阅读历史 Session，发现尚未沉淀的候选知识 | 只报告 |
| `audit` | 检查知识是否过时、重复、冲突、不可验证或放错位置 | 只报告 |

根据用户意图自动选择模式。用户显式指定模式时按其指定执行。

## 触发规则

- 用户明确要求沉淀时，执行 `capture`
- 用户提到以前的讨论、重复故障、历史设计理由或要求搜索对话时，执行 `recall`
- `mine` 和 `audit` 不在普通任务结束时自动运行；需用户要求或明确审计意图

## 候选知识准入

候选必须同时满足：

1. 可复用，将来处理同类任务时会影响判断或执行
2. 非显而易见，不能仅通过当前代码接口或常规文档立即得出
3. 项目相关，不是通用编程知识或个人全局偏好
4. 当前有效，已由当前证据验证
5. 有实际价值，能避免重复故障、错误决策、昂贵调查或不一致实现
6. 边界明确，知道适用模块、场景和条件
7. 载体明确，能判断应进入可执行约束、AGENTS、Skill、ADR、Postmortem 或 README

任一条件不满足，默认不写。高影响、低频事故可以进入 Postmortem，因为价值来自影响和调查成本。

明确拒绝：一次性命令输出与 TODO、强时效信息（版本号）、代码已表达的事实、Assistant 未验证的推测、单次流水账、已有规则的改写、纯通用知识、秘密/凭据/私人对话原文/本机绝对路径。

## Recall

### 当前 Session

Pi 中存在 `vcc_recall` 时优先使用它：默认检索 active lineage，只有历史分支可能影响结论时才用 `scope: "all"`，用 `expand` 展开必要原文。没有 `vcc_recall` 时，只使用当前 Agent 可见上下文，不声称拥有完整当前 Session 历史。

### 跨 Session

1. 把用户问题展开为少量可验证查询词（错误文本、文件路径、函数名、模块名、领域术语、commit、Issue/PR 标识）
2. 默认只搜当前项目；只有用户明确要求才跨项目或含废弃分支：

```sh
bun run --cwd "$PM_DIR" pm -- search "<query>"
bun run --cwd "$PM_DIR" pm -- search "<query>" --all-projects
bun run --cwd "$PM_DIR" pm -- search "<query>" --all-branches
```

3. 用 `show` 安全展开候选上下文（默认脱敏限长，`--no-redact` 出原文，程序消费加 `--format json`）：

```sh
bun run --cwd "$PM_DIR" pm -- show "<session-id>:<entry-id>" --context 5 --max-chars 8000
```

已知目标会话时用选择器避免全项目正文搜索：`show --session previous --entry last-user`、`search "<query>" --session previous`（`--session` 接受完整 ID/唯一前缀/`latest`/`previous`；`--entry` 接受完整 ID/`last`/`last-user`/`last-assistant`）。还原完整因果链用 `show --session previous --transcript`（默认只读 active lineage，`--all-branches` 含废弃分支）。跨项目或废弃分支结果必须重复对应作用域参数。

4. Compaction 和 branch summary 只用于召回与初筛；正式结论必须回到原始 Entry
5. 找到历史结论后，用当前代码、Git、测试或运行结果重新验证再回答

默认只搜索最终 active lineage。废弃分支命中必须标记为 abandoned，并按失败尝试或反向证据处理。

涉及模型纠错/复读时，降智嫌疑判定见 [MINE.md](MINE.md) 分析纪律 #4（不写 rule，只计数）。

## Capture

用户显式调用 `capture` 即代表允许写入；证据、目标或作用域有歧义时，最多询问 1 至 3 个关键问题。

### 写入前检查

1. 收集至少一条历史或当前 Session 证据
2. 收集至少一条当前证据（代码、Git、测试、运行结果或有效文档）
3. 搜索支持和反向记录，确认没有未解决冲突
4. 检查现有代码、自动化、最近 AGENTS、上层 AGENTS、相关 Skill、ADR 和 README
5. 完全相同则不写；只是补充边界时更新原条目；作用域错误时移动或拆分；冲突未解决时停止写入

### 载体路由

按以下顺序判断：

1. 可执行约束：代码、类型、schema、测试、lint、CI 或脚本
2. Agent 必须反复遵守的项目规则：最近作用域的 `AGENTS.md`
3. 包含工具、步骤和判断条件的重复工作流：项目 Skill
4. 重要设计决策、领域术语和取舍：项目已有 ADR/决策文档，必要时使用 `domain-modeling`
5. 高影响事故、复杂故障和根因：项目已有 Postmortem 约定，必要时使用 `postmortem`；用户未明确要求时只建议，不直接写入
6. 用户或贡献者需要了解的稳定行为：README 或普通项目文档

如果更强的可执行约束超出当前任务范围，只提出建议并等待用户确认，不要退而求其次写成 AGENTS 提醒。

### 路径与创建

- 优先遵循项目已有目录、命名、编号和 frontmatter
- AGENTS 使用被影响代码路径最近的已存在文件；未经明确要求不新建
- 项目 Skill 使用项目已有 Skill 目录；编写前读取已有 Skill 风格，相关能力存在时使用 `writing-great-skills`
- ADR 或 Postmortem 没有既有目录时，首次创建前询问用户
- 不把项目专属流程写入全局 Skill

### 生命周期

- AGENTS、项目 Skill、README、普通文档和自动化只保留当前事实；过时内容直接更新或删除
- ADR 使用 Proposed、Accepted、Superseded、Rejected 状态；旧 ADR 被替代时保留原背景并链接新 ADR
- Postmortem 保留历史；后续发现错误时追加勘误，不静默改写事故经过

## Mine

每批最多处理 5 个 unseen 或 changed 的 Session。`mine` 必须先发现高信号问题片段，再按需展开完整会话；不能把摘要或 transcript 数量当成分析结果。

主路径只挖纠错/复读（跨项目，默认脱敏，`--since` 默认 15d，全量 `--since all`）：

```sh
bun run --cwd "$PM_DIR" pm -- mine --since 15d --signals --limit 5 --all-projects \
  --signal-kind user_correction,repeated_user_prompt
```

**详细分析纪律、分析流程、HARVEST、慢命令、信号分类、behavior 分诊见 [MINE.md](MINE.md)。** 分诊要点：首次只跑上面这一条；preset/`--rule` 仅有明确假设时再加；命中必须 `show` 上下文裁决；降智嫌疑不写 rule 只计数。

## Audit

默认只检查当前任务相关范围：修改文件、最近 AGENTS、直接相关 Skill、ADR、README 和 Postmortem。

检查并分类：`valid`（当前仍有效）、`stale`（与代码或事实不符）、`duplicate`（与其他规则重复）、`unverifiable`（找不到当前证据）、`misplaced`（内容正确但载体或作用域错误）、`superseded`（已被新决策替代）。

同时检查：局部规则是否错误写到项目根作用域；可执行约束是否退化成文档提醒；ADR 是否缺少替代关系；Postmortem 修复措施是否仍存在；Skill 是否依赖已不存在的工具。

只有用户明确要求全项目检查或处于重大架构调整、开源、发布阶段时才执行全量 audit。Audit 默认只报告；用户明确要求修复后才修改。

## 冲突裁决

历史记录不按最新时间或出现次数投票。证据优先级：

1. 当前可运行行为、测试和运行时探针
2. 当前代码、类型、schema、CI 和配置
3. 已合并 commit、Issue、PR 和 Accepted ADR
4. 用户在历史中的明确纠正
5. 已验证的历史对话结论
6. Assistant 的历史推测和未完成尝试

无法由当前证据裁决时，标记为 unresolved conflict，停止沉淀并询问用户。

## 项目身份与本地状态

- Git 项目优先使用规范化 remote 作为身份；无 remote 使用 Git 根目录；非 Git 项目使用 cwd
- 已失效 cwd 无法确认归属时默认排除，禁止按目录名猜测
- 用户确认后用 `map-project "<session-id-or-old-cwd>" --to-current` 建立映射
- `status` 查看索引、归属和审阅状态；`rebuild-index` 强制重读 Session 元数据
- 处理完 Session 后用 `mark-reviewed <session-id> --status reviewed` 标记已审阅，避免重复处理；XDG Cache 保存可重建索引与可丢弃审阅状态，删除缓存会重置审阅进度
- XDG Config 只保存用户确认的项目映射；两者都不保存消息正文

## 安全边界

- 默认排除 system、developer、工具调用和工具结果；`mine --transcript` 与 `show --transcript` 是显式例外，用于审阅错误链和因果关系
- 跨 Session 默认限长且脱敏；需要原文用 `--no-redact`。写入项目文件前必须确认无秘密
- 即使获得授权，也不把原始秘密或私人对话写入项目文件
- 不调用外部 Embedding、搜索服务或后台 daemon
- CLI 永远只读原始 Session，不修改 JSONL

## 输出格式

### Recall

```text
查询范围：
历史命中：
当前验证：
冲突与失效信息：
结论：
```

### Mine 候选

```text
候选知识：
适用范围：
为什么值得保留：
历史证据：
当前验证：
反向证据：
建议载体：
未满足条件：
```

### Capture 报告

```text
沉淀内容：
历史证据：
当前证据：
最终载体：
修改文件：
验证方式：
未解决冲突：
```

Session ID 和 Entry ID 只放在运行报告；项目文件只引用代码、测试、commit、Issue、PR 或正式文档等可移植证据。

## 子代理

子代理只可在主代理明确分配时协助只读检索和候选整理。子代理必须返回已审阅 Session ID、相关 Entry ID、错误链或重复模式及候选结论，不能只返回摘要判断。子代理不得写入项目知识、修改审阅状态或继续派生子代理；主代理必须核验其证据和结论后再记录审阅状态。

## 写作格式

优先遵循目标项目已有格式。项目无特别约定时使用中文，正文使用「」而不是弯引号，不用破折号改用逗号或分号。
