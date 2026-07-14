---
name: project-memory
description: 管理项目长期知识，支持 recall、capture、mine、audit 四种模式。用于搜索 Pi 当前或历史 Session、回忆过去决策、从开发过程提炼可复用经验、更新 AGENTS 或项目 Skill、形成 ADR/Postmortem 候选，以及检查项目知识是否过时、重复、冲突或放错位置。跨 Session 检索依赖本机安装的 project-memory CLI（Bun/TS）。
---

# Project Memory

## 目标

把历史对话当作证据源，把项目文件当作唯一长期事实源。检索、验证和路由由本 Skill 协调；跨 Session 读写统一走本机 `project-memory` CLI。具体产物遵循项目约定或对应专用 Skill。

## 本地安装（未公开分发）

CLI 源码在本机开发树，**不**走 npm/GitHub Release 公开分发。

```sh
# 默认路径（按你的实际 clone 位置改）
PM_DIR="${HOME}/Code/active/project-memory"

# 首次
cd "$PM_DIR"
bun install

# 可选：编译单文件二进制并放到 PATH
bun run compile
mkdir -p "${HOME}/.local/bin"
ln -sfn "$PM_DIR/dist/project-memory" "${HOME}/.local/bin/project-memory"
```

日常调用二选一（Skill 下文默认用源码入口，免依赖 PATH）：

```sh
# A. 源码（推荐给 Agent）
bun run --cwd "$PM_DIR" pm -- status

# B. 已 link 的二进制
project-memory status
```

改 CLI 逻辑只动 `PM_DIR` 仓库；本 Skill 只保留工作流与分析纪律，不再内嵌 `scripts/project_memory.py`。

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
4. 任何跨 Session 内容只能通过本机 `project-memory` CLI 读取。**禁止**直接读 Session JSONL，也禁止在业务项目 cwd 下拼相对路径脚本。先定 `$PM_DIR`，之后一律 `bun run --cwd "$PM_DIR" pm -- ...`：

```sh
# 本机源码树（未公开分发；路径按实际安装修改）
PM_DIR="${HOME}/Code/active/project-memory"
test -d "$PM_DIR" || { echo "bad PM_DIR: $PM_DIR — 先按 Skill「本地安装」执行 bun install" >&2; exit 1; }
test -f "$PM_DIR/package.json" || { echo "bad PM_DIR contents: $PM_DIR" >&2; exit 1; }
bun run --cwd "$PM_DIR" pm -- status   # 默认 text；程序用 status --format json
# 若已 compile 并 link 到 PATH，可改用：project-memory status
```

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
bun run --cwd "$PM_DIR" pm -- search "<query>"
```

3. 只有用户明确要求时才跨项目或包含废弃分支：

```sh
bun run --cwd "$PM_DIR" pm -- search "<query>" --all-projects
bun run --cwd "$PM_DIR" pm -- search "<query>" --all-branches
```

4. 使用 `show` 安全展开候选上下文：

```sh
bun run --cwd "$PM_DIR" pm -- show "<session-id>:<entry-id>"
bun run --cwd "$PM_DIR" pm -- show "<session-id>:<entry-id>" --context 5 --max-chars 8000
bun run --cwd "$PM_DIR" pm -- search "<query>" --format json
bun run --cwd "$PM_DIR" pm -- show "<session-id>:<entry-id>" --redact
```

`search` / `show` / `mine` 默认输出可读文本且**默认脱敏**（`--no-redact` 才出原文）；程序消费加 `--format json`。片段默认限长 500，更长用 `--max-chars`。`show` 可用 `--context N` 控制命中前后条目数。条目会尽量标注 `provider/model`；`mine --signals` 为每条信号给出 `error_model` / `recovery_model`。skill 注入的 user 消息、纯谩骂/情绪复读不计入可沉淀信号；同一复读合并为一条并带 `count`。需要按模型汇总时（非首次主路径）：

```sh
bun run --cwd "$PM_DIR" pm -- mine --since 15d --signals --all-projects --by-model --limit 30 \
  --signal-kind user_correction,repeated_user_prompt
bun run --cwd "$PM_DIR" pm -- show "<sid>:<eid>" --context 6 --max-chars 4000
# 需要工具输出再加 --include-tools
```

将 ≥2 次、可写成强制动作的结论**建议**写入对应模型 auto-model-prompt；**默认不直接改文件**，等用户确认。OpenAI/GPT 系若「忽略指令 + 突然低级错/空转」→ **降智嫌疑**（不写 rule，只可计数）。分析纪律见 **Mine** 节。

### 无报错怪癖与 session 脉络

**规则与频率由 agent 传入，脚本不替 agent 做判断。** 默认不启用 `behavior_risk`；需要时按假设传入规则，**命中后必须 `show` 上下文判断是否真错**，禁止用 regex 命中反推「模型又犯已知错误」。

行为扫描只看 **被执行的 bash 命令**（忽略 toolResult）；侦察类命令不计。`matched` 仅供核验，不是定罪。

有明确假设时才用 behavior 规则（**不是首次入口**）：

```sh
# 规则：id::regex::title（:: 分隔，避免正则里的 |）
bun run --cwd "$PM_DIR" pm -- mine --signals --all-projects \
  --rule 'git_add_all::\bgit\s+add\s+-A::禁止 add -A' \
  --signal-kind behavior_risk,user_correction

bun run --cwd "$PM_DIR" pm -- show --session <sid> --outline \
  --rule 'git_reset_hard::\bgit\s+reset\s+--hard\b::禁止 hard reset'

bun run --cwd "$PM_DIR" pm -- mine --signals --rules-file rules.json --signal-kind behavior_risk
bun run --cwd "$PM_DIR" pm -- mine --signals --preset-behaviors --signal-kind behavior_risk
```

分诊约定：
- **首次只跑 HARVEST 那一条**（见 Mine 节）：纠错/复读 + `--all-projects`；不要一上来 preset
- `mine --signals` **默认 text**（程序消费显式 `--format json`）
- text 优先**有技术内容**的纠错/复读；纯降智空转句 **折叠**为 `degradation-like`；`command_failure` **默认折叠**
- 同 rule 的 behavior 合并为一条并带 `count`；纠错/复读/CF 对 `problem_score` 有封顶
- `--preset-behaviors` / `--rule` **仅有假设时**再加；命中须 Jump 上下文裁决
- `--correction-marker` 等 **追加** 默认词表；覆盖用 `--replace-markers`
- 非法 `--signal-kind` / 坏正则 / 用 `|` 当分隔 → stderr 报错退出
- 仅要 `behavior_risk` 却不传规则 → 直接报错；也可用 `--rules-file rules.json`
- `show` 找不到 session 自动 all-projects；context **TARGET 置顶**；`Jump:` 完整可复制
- cwd 无 session 时 warning 提示 `--all-projects` / `--project-dir`

其它旋钮：`--repeated-threshold` / `--min-prompt-len` / `--episode-radius*`、
`--no-emotional-filter` / `--no-skill-filter` / `--outline-max-*` / `--context` / `--max-chars`。

单点展开（可直接粘贴 Jump）：

```sh
bun run --cwd "$PM_DIR" pm -- show "<sid>:<eid>" --context 6 --max-chars 3000
```

   已知目标会话时，可用通用会话和条目选择器避免全项目正文搜索：

```sh
bun run --cwd "$PM_DIR" pm -- show --session previous --entry last-user
bun run --cwd "$PM_DIR" pm -- search "<query>" --session previous
```

   `--session` 接受完整会话 ID、唯一前缀、`latest` 或 `previous`；`--entry` 接受完整条目 ID、`last`、`last-user` 或 `last-assistant`。`show "<session-id>:<entry-id>"` 仍适用于搜索结果。

   需要还原一个 Session 的完整用户、助手和工具因果链时，使用 VCC 风格的会话流：

```sh
bun run --cwd "$PM_DIR" pm -- show --session previous --transcript
bun run --cwd "$PM_DIR" pm -- show --session previous --transcript --all-branches
```

   前者只读 active lineage，后者包含 abandoned 分支。会话流会保留角色、工具调用、工具结果和失败标记；默认脱敏且限长，需要原文时加 `--no-redact`。

   跨项目或废弃分支的结果必须重复对应作用域参数：

```sh
bun run --cwd "$PM_DIR" pm -- show "<session-id>:<entry-id>" --all-projects
bun run --cwd "$PM_DIR" pm -- show "<session-id>:<entry-id>" --all-branches
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

### 分析纪律（强制）

目标：从上下文里挖**可沉淀信息**。做不到就写「无」。禁止堆噪音表、session 流水账。

1. **模型归属到 message**：`error_model` + entry 的 `provider/model`；禁止整场 session 记到一个模型。
2. **上下文裁决，禁止命令枚举定罪**：`behavior_risk`/preset 只是检索线索。必须 `show` 前后文判断当轮是否真错。用户允许的 force、容器内 find、只读侦察、提问句、证据不足 → **不是错误**。
3. **脚本价值 = 前后文**：用 Jump/`show --context` 读链，不用 mine 列表当终审。
4. **降智嫌疑（尤其 GPT 系）**：若同时出现「明显忽略用户指令」+「突然低级错误/空转/格式自限/情绪对骂式复读」，标 **降智嫌疑**，**不要当错误展开分析，不要写 rule**（rule 纠不了降智）。只可在汇总里一行计数。
5. **单次纠正 ≠ rule**：产品偏好、一次性指偏、证据不足的质疑句 → 丢弃。rule 需要可复用强制动作，且最好 ≥2 次非降智样本，或上下文证明系统性做错。
6. **已在 auto-model-prompt / AGENTS 出现过的** → 不输出；最多内部记「执行失败」，不写进汇报正文。
7. **汇报只保留有价值信息**（维度：项目 + 模型，不要 session 流水账）：
   - 建议 rule（简洁正文；无则「无」）
   - 用户习惯（跨上下文稳定偏好；无则「无」）
   - 降智嫌疑（模型 + 一句特征/计数；**不写 rule**）
   - 禁止：情绪词统计、已知禁令再清单、证据不足条目、降智过程复述
8. **默认不改** auto-model-prompt 文件，除非用户当轮明确要求写入。

### 分析流程（重做）

```
mine 纠错/复读 → Jump 读上下文 → 分类 → 只留下「可沉淀」
分类桶：
  A 降智嫌疑 → 丢弃（可计数）
  B 已有 rule → 丢弃（不汇报）
  C 单次/非错误/证据不足 → 丢弃
  D 可沉淀 rule / 稳定用户习惯 → 写入对应表
```

### HARVEST

主路径只挖纠错/复读（跨项目，默认脱敏）。`--signals` 未写 `--since` 时默认 **15d**（全量：`--since all`）。preset 仅有**明确假设**时再加，命中仍须分类 A–D：

```sh
bun run --cwd "$PM_DIR" pm -- mine --since 15d --signals --limit 5 --all-projects \
  --signal-kind user_correction,repeated_user_prompt
# 有假设时再加 --preset-behaviors / --rule（不是定罪）
```

`--signals` 只返回有问题信号的 Session。排序：**技术向纠错优先**（`tech_score`），纯降智空转靠后；有 behavior 时 behavior 数仍最高。text 把 `degradation-like` 折叠成一行。

- `user_correction`（3 分）：紧跟 Assistant 回答并包含明确纠正表达的用户消息。**分析主入口。**
- `repeated_user_prompt`（3 分）：Unicode 规范化后相同或相似度至少 0.86 的用户 Prompt；超过 500 字时只接受规范化后完全相同。
- `behavior_risk`（4 分）：assistant 实际执行的 bash 命中 `--rule` / `--preset-behaviors`（需显式启用）。**仅候选。**
- `command_failure`（单条 2 分，session 总分最多计 2；text 默认折叠）：连续错误链。

每个信号含 Entry ID、`error_model`/`recovery_model`、脱敏 Episode。信号是高召回候选，**不等于** Agent 一定犯错；必须主代理结合 Episode/`show` 裁决。

时间窗：相对 `15d` 或 ISO；未写 `--since` 时 `--signals` 默认 15d（全量 `--since all`）。大输出用 `--format ndjson`。

Episode/`--context` 仍不够时，再整页读该 session（**不是首次入口**）：

```sh
bun run --cwd "$PM_DIR" pm -- show --session "<session-id>" --transcript \
  --offset 0 --limit 50 --full-content --format json
```

用 `transcript_page.next_offset` 翻页直到 `null`。assistant 按各自 `model` 归属。仍不够再 `--all-branches`。

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
bun run --cwd "$PM_DIR" pm -- map-project "<session-id-or-old-cwd>" --to-current
```

- `status` 查看索引、归属和审阅状态；`rebuild-index` 强制重读 Session 元数据。
- XDG Cache 保存可重建索引和可丢弃审阅状态；删除缓存会重置审阅进度。XDG Config 只保存用户确认的项目映射；两者都不保存消息正文。

## 安全边界

- 默认排除 system、developer、工具调用和工具结果；`mine --transcript` 与 `show --transcript` 是显式例外，用于审阅错误链和因果关系。
- 跨 Session 默认限长且脱敏；需要原文用 `--no-redact`。写入项目文件前必须确认无秘密。
- 未经明确授权，不把含秘密的历史原文写入项目文件。
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
