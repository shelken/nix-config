---
name: project-memory
description: 管理项目长期知识，支持 recall、capture、mine、audit 四种模式。用于搜索 Pi 当前或历史 Session、回忆过去决策、从开发过程提炼可复用经验、更新 AGENTS 或项目 Skill、形成 ADR/Postmortem 候选，以及检查项目知识是否过时、重复、冲突或放错位置。
---

# Project Memory

## 目标

把历史对话当作证据源，把项目文件当作唯一长期事实源。检索、验证和路由由本 Skill 协调；具体产物遵循项目约定或对应专用 Skill。

## 核心原则

- Session 只提供候选证据，不能直接成为项目事实。
- 正式知识必须结合当前代码、Git、测试、运行结果或有效文档验证。
- 能通过代码、类型、schema、测试、lint、CI 或脚本保证的约束，优先做成可执行约束。
- 写入前先检查现有实现、规则、作用域和重复内容，优先更新、移动或删除原内容。
- Session 路径、Entry ID 和对话片段只出现在运行报告中，不写入 Git。
- 不建立独立的项目事实库；本地索引和审阅状态只是可丢弃辅助状态，不是项目事实源。

## 模式选择

| 模式 | 用途 | 默认写入权限 |
|---|---|---|
| `recall` | 回忆当前或历史对话，回答过去如何决策或处理 | 只读 |
| `capture` | 提炼当前任务中已验证的长期知识 | 证据和目标明确时可写 |
| `mine` | 分批阅读历史 Session，发现尚未沉淀的候选知识 | 只报告 |
| `audit` | 检查知识是否过时、重复、冲突、不可验证或放错位置 | 只报告 |

根据用户意图自动选择模式。用户显式指定模式时按其指定执行。

## 触发规则

普通任务结束时只做一次轻量判断：是否出现非显而易见、可复用、已验证，并能避免未来成本的知识。

- 没有候选时直接结束，不提项目记忆。
- 有候选但用户未要求沉淀时，只用一句话说明候选和建议载体。
- 用户明确要求沉淀时，执行 `capture`。
- 用户提到以前的讨论、重复故障、历史设计理由或要求搜索对话时，执行 `recall`。
- `mine` 和 `audit` 不在普通任务结束时自动运行。

## 公共准备

1. 确认当前项目根目录、最近作用域的 `AGENTS.md` 和项目约定。
2. 查看相关代码、Git 状态、测试、文档和 Postmortem 标题。
3. 判断当前操作属于哪种模式。
4. 任何跨 Session 内容只能通过 `scripts/project_memory.py` 读取；执行前将该相对路径解析为本 Skill 目录下的实际路径。

## Recall

### 当前 Session

Pi 中存在 `vcc_recall` 时优先使用它：

- 默认检索 active lineage。
- 只有历史分支可能影响结论时才使用 `scope: "all"`。
- 用 `expand` 展开必要原文，不重复实现 VCC 已有能力。

没有 `vcc_recall` 时，只使用当前 Agent 可见上下文，不声称拥有完整当前 Session 历史。

### 跨 Session

1. 把用户问题展开为少量可验证查询词，例如错误文本、文件路径、函数名、模块名、领域术语、commit、Issue 或 PR 标识。
2. 默认只搜索当前 Git 项目：

```sh
python3 scripts/project_memory.py search "<query>"
```

3. 只有用户明确要求时才跨项目或包含废弃分支：

```sh
python3 scripts/project_memory.py search "<query>" --all-projects
python3 scripts/project_memory.py search "<query>" --all-branches
```

4. 使用 `show` 安全展开候选上下文：

```sh
python3 scripts/project_memory.py show "<session-id>:<entry-id>"
```

   已知目标会话时，可用通用会话和条目选择器避免全项目正文搜索：

```sh
python3 scripts/project_memory.py show --session previous --entry last-user
python3 scripts/project_memory.py search "<query>" --session previous
```

   `--session` 接受完整会话 ID、唯一前缀、`latest` 或 `previous`；`--entry` 接受完整条目 ID、`last`、`last-user` 或 `last-assistant`。`show "<session-id>:<entry-id>"` 仍适用于搜索结果。

   需要还原一个 Session 的完整用户、助手和工具因果链时，使用 VCC 风格的会话流：

```sh
python3 scripts/project_memory.py show --session previous --transcript
python3 scripts/project_memory.py show --session previous --transcript --all-branches
```

   前者只读 active lineage，后者包含 abandoned 分支。会话流会保留角色、工具调用、工具结果和失败标记，但仍经过脱敏与限长。

   跨项目或废弃分支的结果必须重复对应作用域参数：

```sh
python3 scripts/project_memory.py show "<session-id>:<entry-id>" --all-projects
python3 scripts/project_memory.py show "<session-id>:<entry-id>" --all-branches
```

5. 默认不包含工具调用和工具结果；只有错误或命令输出是必要证据时才使用 `--include-tools`。
6. 禁止绕过 CLI 直接读取跨 Session JSONL。
7. Compaction 和 branch summary 只用于召回与初筛；正式结论必须回到原始 Entry。
8. 找到历史结论后，用当前代码、Git、测试或运行结果重新验证再回答。

默认只搜索最终 active lineage。废弃分支命中必须标记为 abandoned，并按失败尝试或反向证据处理。

## 候选知识准入

候选必须同时满足：

1. 可复用，将来处理同类任务时会影响判断或执行。
2. 非显而易见，不能仅通过当前代码接口或常规文档立即得出。
3. 项目相关，不是通用编程知识或个人全局偏好。
4. 当前有效，已由当前证据验证。
5. 有实际价值，能避免重复故障、错误决策、昂贵调查或不一致实现。
6. 边界明确，知道适用模块、场景和条件。
7. 载体明确，能判断应进入可执行约束、AGENTS、Skill、ADR、Postmortem 或 README。

任一条件不满足，默认不写。高影响、低频事故可以进入 Postmortem，因为价值来自影响和调查成本。

明确拒绝：

- 一次性命令输出、临时任务状态和 TODO。
- 当前版本号等强时效信息。
- 代码已经清楚表达的事实。
- Assistant 未验证的推测和无根因的失败尝试。
- 单次操作流水账、已有规则的改写和纯通用知识。
- 秘密、凭据、私人对话原文和本机绝对路径。

## Capture

用户显式调用 `capture` 即代表允许写入；证据、目标或作用域有歧义时，最多询问 1 至 3 个关键问题。

### 写入前检查

1. 收集至少一条历史或当前 Session 证据。
2. 收集至少一条当前证据，例如代码、Git、测试、运行结果或有效文档。
3. 搜索支持和反向记录，确认没有未解决冲突。
4. 检查现有代码、自动化、最近 AGENTS、上层 AGENTS、相关 Skill、ADR 和 README。
5. 完全相同则不写；新知识只是补充边界时更新原条目；作用域错误时移动或拆分；冲突未解决时停止写入。

### 载体路由

按以下顺序判断：

1. 可执行约束：代码、类型、schema、测试、lint、CI 或脚本。
2. Agent 必须反复遵守的项目规则：最近作用域的 `AGENTS.md`。
3. 包含工具、步骤和判断条件的重复工作流：项目 Skill。
4. 重要设计决策、领域术语和取舍：项目已有 ADR/决策文档，必要时使用 `domain-modeling`。
5. 高影响事故、复杂故障和根因：项目已有 Postmortem 约定，必要时使用 `postmortem`；用户未明确要求时只建议，不直接写入。
6. 用户或贡献者需要了解的稳定行为：README 或普通项目文档。

如果更强的可执行约束超出当前任务范围，只提出建议并等待用户确认，不要退而求其次写成 AGENTS 提醒。

### 路径与创建

- 优先遵循项目已有目录、命名、编号和 frontmatter。
- AGENTS 使用被影响代码路径最近的已存在文件；未经明确要求不新建。
- 项目 Skill 使用项目已有 Skill 目录；编写前读取已有 Skill 风格，相关能力存在时使用 `writing-great-skills`。
- ADR 或 Postmortem 没有既有目录时，首次创建前询问用户。
- 不把项目专属流程写入全局 Skill。

### 生命周期

- AGENTS、项目 Skill、README、普通文档和自动化只保留当前事实；过时内容直接更新或删除。
- ADR 使用 Proposed、Accepted、Superseded、Rejected 状态；旧 ADR 被替代时保留原背景并链接新 ADR。
- Postmortem 保留历史；后续发现错误时追加勘误，不静默改写事故经过。

## Mine

每批最多处理 5 个当前项目中 unseen 或 changed 的 Session。`mine` 必须先发现高信号问题片段，再按需展开完整会话；不能把摘要或 transcript 数量当成分析结果。

先运行 HARVEST 信号探测：

```sh
python3 scripts/project_memory.py mine --signals
```

`--signals` 扫描筛选范围后按 `problem_score` 排序，只返回存在问题信号的 Session：

- `command_failure`（2 分）：同一分支上具有直接父子关系的一个或多个连续 Assistant、toolResult 或 bashExecution 错误。
- `repeated_user_prompt`（3 分）：Unicode 规范化后相同或相似度至少 0.86 的用户 Prompt；超过 500 字时只接受规范化后完全相同，避免共同长前缀掩盖关键尾部差异。
- `user_correction`（3 分）：紧跟 Assistant 回答并包含明确纠正表达的用户消息。

每个信号包含原始 Entry ID 和脱敏 Episode。信号是高召回候选，不等于 Agent 一定犯错；必须由主代理结合 Episode 裁决。

需要限定审阅时间窗口时，使用通用时间边界；筛选发生在 `--limit` 之前，并以 Session 文件最后更新时间为准。边界包含等值，接受 `15d` 这类相对天数或 ISO 8601 时间：

```sh
python3 scripts/project_memory.py mine --since 15d --signals
python3 scripts/project_memory.py mine --since 2026-06-25 --until 2026-07-10 --signals
```

输出较大时使用 NDJSON。输出依次为 `meta`、`session`、逐条 `signal`、`transcript` 或 `item`，以及可选的 `warning`，每行都是独立 JSON：

```sh
python3 scripts/project_memory.py mine --since 15d --signals --format ndjson
```

流程：

1. 逐个审阅信号 Episode，并回答：用户原要求是什么、Agent 做了什么判断或行动、哪条工具结果或用户消息推翻了它、是否重复同一错误、最终如何修正、是否形成可复用反模式。重复 Prompt 还要判断是 Agent 忽略要求、偏离任务、错误宣称完成，还是用户主动补充需求。
2. Episode 不足以裁决因果链时，再展开该 Session 的完整 active lineage：

```sh
python3 scripts/project_memory.py show --session "<session-id>" --transcript
```

`--transcript` 以 VCC 风格输出 user、assistant、toolResult、bashExecution 和 summary，并保留 Entry ID、时间、分支状态与 `is_error`。
3. 如果被放弃的诊断分支可能解释错误根因、反复尝试或用户纠正，重跑：

```sh
python3 scripts/project_memory.py show --session "<session-id>" --transcript --all-branches
```

4. 完成问题信号审阅后，再用普通 `mine` 检查没有错误信号但可能包含决策、规则或待定问题的 Session。summary 只辅助导航，不能单独排除候选。
5. 对每个候选回到原始 Entry，再按「候选知识准入」结合当前代码、Git、测试或运行结果验证。没有候选也必须说明已检查的信号、错误链和反向证据。
6. 只有主代理在核验子代理或自身的审阅结论后，才记录状态：

```sh
python3 scripts/project_memory.py mark-reviewed "<session-id>" --status reviewed
python3 scripts/project_memory.py mark-reviewed "<session-id>" --status pending --candidate-count <n>
python3 scripts/project_memory.py mark-reviewed "<session-id>" --status resolved
```

状态含义：

- `unseen`：未审阅。
- `reviewed`：已审阅，没有候选。
- `pending`：发现候选，尚未沉淀或放弃。
- `resolved`：候选已沉淀或明确放弃。
- `changed`：Session 在上次审阅后发生变化，由 CLI 派生并重新进入队列。

`mine` 默认不重复处理 pending。候选正文不写入本地索引。

## Audit

默认只检查当前任务相关范围：修改文件、最近 AGENTS、直接相关 Skill、ADR、README 和 Postmortem。

检查并分类：

- `valid`：当前仍有效。
- `stale`：与代码或事实不符。
- `duplicate`：与其他规则重复。
- `unverifiable`：找不到当前证据。
- `misplaced`：内容正确但载体或作用域错误。
- `superseded`：已被新决策替代。

同时检查：

- 局部规则是否错误写到项目根作用域。
- 可执行约束是否退化成文档提醒。
- ADR 是否缺少替代关系。
- Postmortem 修复措施是否仍存在。
- Skill 是否依赖已不存在的工具。

只有用户明确要求全项目检查或处于重大架构调整、开源、发布阶段时才执行全量 audit。Audit 默认只报告；用户明确要求修复后才修改。

## 冲突裁决

历史记录不按最新时间或出现次数投票。证据优先级：

1. 当前可运行行为、测试和运行时探针。
2. 当前代码、类型、schema、CI 和配置。
3. 已合并 commit、Issue、PR 和 Accepted ADR。
4. 用户在历史中的明确纠正。
5. 已验证的历史对话结论。
6. Assistant 的历史推测和未完成尝试。

无法由当前证据裁决时，标记为 unresolved conflict，停止沉淀并询问用户。

## 项目身份与本地状态

- Git 项目优先使用规范化 remote 作为身份；无 remote 使用 Git 根目录；非 Git 项目使用 cwd。
- 已失效 cwd 无法确认归属时默认排除，禁止按目录名猜测。
- 用户确认后使用映射：

```sh
python3 scripts/project_memory.py map-project "<session-id-or-old-cwd>" --to-current
```

- `status` 查看索引、归属和审阅状态；`rebuild-index` 强制重读 Session 元数据。
- XDG Cache 保存可重建索引和可丢弃审阅状态；删除缓存会重置审阅进度。XDG Config 只保存用户确认的项目映射；两者都不保存消息正文。

## 安全边界

- 默认排除 system、developer、工具调用和工具结果；`mine --transcript` 与 `show --transcript` 是经脱敏的显式例外，用于审阅错误链和因果关系。
- 跨 Session 片段必须先经过 CLI 脱敏和限长。
- 未经明确授权，不读取未脱敏历史内容。
- 即使获得授权，也不把原始秘密或私人对话写入项目文件。
- 不调用外部 Embedding、搜索服务或后台 daemon。
- CLI 永远只读原始 Session，不修改 JSONL。

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

优先遵循目标项目已有格式。项目没有特别约定时：

- 使用中文。
- 禁止用破折号，改用逗号或分号。
- 中文正文使用「」而不是弯引号。
