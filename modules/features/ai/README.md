# ai

Agent 相关配置，按能力组织（ADR 0008）。`ai` 是跑 agent 的机器都需要的运行时；只在工作站使用的能力是独立功能，各自加入 `workstation`

## ai 本体（运行时）

| 路径 | 内容 |
|---|---|
| `omp/`、`pi/` | 两个 agent harness 的配置、模型、插件、扩展 |
| `agents/` | 子代理定义与提示词；`spawn-subagent.nix` 在宿主终端开子代理窗格 |
| `agent.nix`、`_agents.md` | 全局 AGENTS.md 及其部署目标 |
| `skill.nix`、`skills/` | skill 唯一入口 `shelken.dev.ai.skills`：选项挂在 core、部署、`ai` 需要的通用 skill（本地 `skills/` 与外部 input），以及 CI 读的 `flake.skillUpstreams`（ADR 0009） |
| `tools.nix` | 共享工具登记表中 omp、pi、bun 的条目（ADR 0003） |
| `plugins.nix`、`auto-model-prompts/` | omp 与 pi 共用的插件配置、按模型注入的提示词 |
| `cli.nix` | skill 与 harness 依赖的 CLI（ctx7、deepwiki、lit、agent-browser、herdr、rtk 等） |
| `agent-gh/` | agent 专属 GitHub 身份的 gh 包装 |
| `sandbox/` | Agent 沙箱（sb），设计见其 README |
| `darwin.nix` | 让 `ai` 加入 workstation |

## 独立功能（只在工作站）

| 路径 | 功能名 | 内容 |
|---|---|---|
| `iphone/` | `iphone` | 控制 USB 连接的 iPhone：skill、`iphone` 命令、swipt |
| `computer-use/` | `computer-use` | 控制宿主桌面：skill、cua-driver cask |
| `ai-apps/` | `ai-apps` | AI 桌面 App（openusage、alma）与宿主专用客户端（codex、claude-code、antigravity-cli） |
| `scrub-words/` | `scrub-words` | 按本地字典替换会话里的脏话 |
| `orca/` | `orca` | Orca 键位 |
| `session-archive/` | `session-archive` | 归档冷会话，设计见其 README |

## 新增配置放哪

先问：执行节点上跑在沙箱里的 agent 用不用得到？用得到放 `ai` 本体；用不到就新建一个能力目录，自带 skill（登记到 `shelken.dev.ai.skills`）、命令、cask 和沙箱桩（`shelken.dev.sandbox.hostCommands`），并自行加入角色
