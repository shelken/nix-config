---
name: project-memory
description: 项目长期知识的召回与沉淀。recall：回忆历史对话中的讨论、重复故障、设计理由；capture：沉淀本轮已验证的经验。mine（挖掘未沉淀候选）与 audit（检查知识过时或错位）仅在用户显式要求时运行。
---

# Project Memory

## 目标

把历史对话当作证据源，把项目文件当作唯一长期事实源。本 Skill 协调检索、验证和路由；跨 Session 读写统一走本机 `project-memory` CLI；具体产物遵循项目约定或对应专用 Skill。

## 模式选择

| 模式 | 用途 | 默认写入权限 | 进入前先读 |
|---|---|---|---|
| `recall` | 回忆当前或历史对话，回答过去如何决策或处理 | 只读 | [RECALL.md](RECALL.md) |
| `capture` | 提炼当前任务中已验证的长期知识 | 证据和目标明确时可写 | [CAPTURE.md](CAPTURE.md) |
| `mine` | 分批阅读历史 Session，发现尚未沉淀的候选知识 | 只报告 | [MINE.md](MINE.md) |
| `audit` | 检查知识是否过时、重复、冲突、不可验证或放错位置 | 只报告 | 本文件「Audit」 |

根据用户意图自动选择模式。用户显式指定模式时按其指定执行。

## 触发规则

- 用户明确要求沉淀时，执行 `capture`
- 用户提到以前的讨论、重复故障、历史设计理由或要求搜索对话时，执行 `recall`
- 用户仅调用本技能、没有额外指示时，检查本轮对话中值得沉淀的经验与教训；有候选时，向用户反馈建议记录到哪些文档，如 AGENTS、Skill 或尸检报告（载体判断与各载体约束读 [CAPTURE.md](CAPTURE.md)）
- `mine` 和 `audit` 不在普通任务结束时自动运行；需用户要求或明确审计意图

## 调用约定

CLI 源码在本机开发树，不走 npm/GitHub；首次安装见 [INSTALL.md](INSTALL.md)。先设定 `$PM_DIR`，之后一律用 `bun run --cwd "$PM_DIR" pm -- <cmd>`（已 link 到 PATH 时可用 `project-memory <cmd>`）：

```sh
PM_DIR="${HOME}/Code/active/project-memory"
test -d "$PM_DIR" || { echo "bad PM_DIR: $PM_DIR — 见 INSTALL.md" >&2; exit 1; }
test -f "$PM_DIR/package.json" || { echo "bad PM_DIR contents: $PM_DIR" >&2; exit 1; }
bun run --cwd "$PM_DIR" pm -- status   # 默认 text；程序用 status --format json
```

跨 Session 内容只能通过本机 CLI 读取。**禁止**直接读 Session JSONL，**禁止**在业务项目 cwd 下拼相对路径脚本。各命令完整 flag 见 `<cmd> --help`。

## 核心原则

- Session 只提供候选证据，不直接成为项目事实
- 正式知识必须结合当前代码、Git、测试、运行结果或有效文档验证
- 能通过代码、类型、schema、测试、lint、CI 或脚本保证的约束，优先做成可执行约束
- 写入前先检查现有实现、规则、作用域和重复内容，优先更新、移动或删除原内容
- Session 路径、Entry ID 和对话片段只出现在运行报告中，不写入 Git；项目文件只引用代码、测试、commit、Issue、PR 或正式文档等可移植证据
- 不建立独立的项目事实库；本地索引和审阅状态只是可丢弃辅助状态，不是项目事实源

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

## Audit

默认只检查当前任务相关范围：修改文件、最近 AGENTS、直接相关 Skill、ADR、README 和 Postmortem。

逐项分类：`valid`（当前仍有效）、`stale`（与代码或事实不符）、`duplicate`（与其他规则重复）、`unverifiable`（找不到当前证据）、`misplaced`（内容正确但载体或作用域错误）、`superseded`（已被新决策替代）。

同时检查：局部规则是否错误写到项目根作用域；可执行约束是否退化成文档提醒；ADR 是否缺少替代关系；Postmortem 修复措施是否仍存在；Skill 是否依赖已不存在的工具。

只有用户明确要求全项目检查，或处于重大架构调整、开源、发布阶段时才执行全量 audit。Audit 默认只报告；用户明确要求修复后才修改。

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
- 处理完 Session 后用 `mark-reviewed <session-id> --status reviewed` 标记已审阅，避免重复处理
- XDG Cache 保存可重建索引与可丢弃审阅状态，删除缓存会重置审阅进度；XDG Config 只保存用户确认的项目映射；两者都不保存消息正文

## 安全边界

- 默认排除 system、developer、工具调用和工具结果；`mine --transcript` 与 `show --transcript` 是显式例外，用于审阅错误链和因果关系
- 跨 Session 默认限长且脱敏；需要原文用 `--no-redact`。写入项目文件前必须确认无秘密
- 即使获得授权，也不把原始秘密或私人对话写入项目文件
- 不调用外部 Embedding、搜索服务或后台 daemon
- CLI 永远只读原始 Session，不修改 JSONL

## 子代理

子代理只可在主代理明确分配时协助只读检索和候选整理。子代理必须返回已审阅 Session ID、相关 Entry ID、错误链或重复模式及候选结论，不能只返回摘要判断。子代理不得写入项目知识、修改审阅状态或继续派生子代理；主代理必须核验其证据和结论后再记录审阅状态。

## 写作格式

优先遵循目标项目已有格式。项目无特别约定时使用中文，正文使用「」而不是弯引号，不用破折号改用逗号或分号。
