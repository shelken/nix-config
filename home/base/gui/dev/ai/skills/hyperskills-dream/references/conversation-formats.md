# Conversation Format Reference

本参考用于 `hyperskills-dream`。读取顺序：Pi sessions → Claude Code sessions → Codex
sessions。Pi 是主要 client；其他来源用于补充工程事实、决策和错误模式。

所有 JSONL 都先用 Python 解析，再按真实字段处理。grep 只用于初步筛选。

## Pi JSONL

**Location:** `~/.pi/agent/sessions/<encoded-path>/**/*.jsonl` **Encoding:**
项目路径会编码成目录名，例如 `/Users/shelken/nix-config` → `--Users-shelken-nix-config--`。

### Session Discovery

```bash
# 当前项目最近 Pi sessions
find ~/.pi/agent/sessions/--Users-shelken-nix-config-- -name "*.jsonl" -mtime -7 -exec ls -lhS {} + | head -30

# 全局最近 Pi sessions
find ~/.pi/agent/sessions -name "*.jsonl" -mtime -7 -exec ls -lhS {} + | head -50

# 大会话通常信息密度更高
find ~/.pi/agent/sessions -name "*.jsonl" -mtime -7 -size +100k -exec ls -lhS {} + | head -30
```

### Message Structure

Pi session JSONL 常见记录类型：

| Type                    | Purpose              | Key Fields                                      |
| ----------------------- | -------------------- | ----------------------------------------------- |
| `session`               | 会话头               | `id`, `cwd`, `parentSession`, `version`         |
| `message`               | 用户、助手、工具消息 | `message.role`, `message.content`, `toolName`   |
| `custom`                | Pi UI / 状态事件     | `customType`, `data`                            |
| `thinking_level_change` | thinking level 变化  | `thinkingLevel`                                 |
| `model_change`          | 模型切换             | `provider`, `modelId`                           |
| `compaction`            | 压缩摘要             | `summary`, `details.readFiles`, `modifiedFiles` |
| `session_info`          | 会话元信息           | `name`                                          |

`message` 里的常见字段：

| Field                  | Meaning                              |
| ---------------------- | ------------------------------------ |
| `message.role`         | `user` / `assistant` / tool 相关角色 |
| `message.content`      | 文本或结构化内容                     |
| `message.toolName`     | 工具名                               |
| `message.toolCallId`   | 工具调用 id                          |
| `message.isError`      | 工具或模型错误标记                   |
| `message.errorMessage` | 错误文本                             |
| `message.provider`     | 模型提供方                           |
| `message.model`        | 模型名                               |

Pi schema 会随版本变化。Dream 处理时以当前 JSONL 字段为准。

### Useful Python Patterns

```bash
# 查看记录类型分布
python3 - <<'PY'
import json, collections
from pathlib import Path
p = Path('session.jsonl')
counts = collections.Counter()
for line in p.open(errors='ignore'):
    obj = json.loads(line)
    counts[obj.get('type')] += 1
print(counts)
PY

# 提取用户消息
python3 - <<'PY'
import json
with open('session.jsonl', errors='ignore') as f:
    for line in f:
        obj = json.loads(line)
        if obj.get('type') != 'message':
            continue
        msg = obj.get('message', {})
        if msg.get('role') == 'user':
            text = msg.get('content', '')
            if isinstance(text, str) and len(text) > 20:
                print(text[:500])
                print('---')
PY

# 提取工具错误
python3 - <<'PY'
import json
with open('session.jsonl', errors='ignore') as f:
    for line in f:
        obj = json.loads(line)
        if obj.get('type') != 'message':
            continue
        msg = obj.get('message', {})
        if msg.get('isError') or msg.get('errorMessage'):
            print(obj.get('timestamp'), msg.get('toolName'), msg.get('errorMessage', '')[:300])
PY

# 提取压缩摘要里的读写文件
python3 - <<'PY'
import json
with open('session.jsonl', errors='ignore') as f:
    for line in f:
        obj = json.loads(line)
        if obj.get('type') == 'compaction':
            print(obj.get('summary', '')[:1000])
            print(obj.get('details', {}))
PY
```

### Pi Signals Worth Extracting

| Signal               | Where to Look                           | Hindsight Memory Shape       |
| -------------------- | --------------------------------------- | ---------------------------- |
| 用户修正 agent 理解  | `message.role == "user"` 后续内容       | 反模式 / 规则                |
| 工具错误后成功处理   | `message.isError` → 后续成功工具调用    | 反模式 / 模式                |
| 压缩摘要             | `type == "compaction"`                  | 决策 / 已完成工作 / 待定问题 |
| 修改文件列表         | `details.modifiedFiles`                 | 项目上下文                   |
| 模型或 thinking 变化 | `model_change`, `thinking_level_change` | 仅在影响结果质量时记录       |

---

## Claude Code JSONL

**Location:** `~/.claude/projects/<encoded-path>/<session-uuid>.jsonl` **Encoding:**
路径分隔符会替换为 `-`。

### Message Structure

每行是一个完整 JSON 对象：

```json
{
  "uuid": "unique-message-id",
  "parentUuid": "previous-message-uuid | null",
  "isSidechain": false,
  "type": "user | assistant | system | progress",
  "timestamp": "2026-04-04T22:15:00.000Z",
  "cwd": "/Users/user/dev/project",
  "sessionId": "session-uuid",
  "message": {
    "role": "user | assistant",
    "content": "..."
  }
}
```

### Content Formats by Role

用户消息通常是字符串。助手消息常见为 typed blocks：

```json
[
  { "type": "thinking", "thinking": "internal reasoning..." },
  { "type": "text", "text": "visible response..." },
  { "type": "tool_use", "id": "toolu_...", "name": "Bash", "input": { "command": "ls" } }
]
```

### Metadata Entries (Non-Message Lines)

| Type                    | Purpose      | Key Fields                          |
| ----------------------- | ------------ | ----------------------------------- |
| `summary`               | 压缩摘要     | `leafUuid`, `summary`               |
| `ai-title`              | 自动标题     | `aiTitle`                           |
| `custom-title`          | 用户标题     | `customTitle`                       |
| `tag`                   | 会话标签     | `tag`                               |
| `last-prompt`           | 最后用户提示 | `lastPrompt`                        |
| `pr-link`               | PR 关联      | `prNumber`, `prUrl`, `prRepository` |
| `file-history-snapshot` | 文件状态快照 | `messageId`, `snapshot`             |
| `mode`                  | 模式信息     | `mode`                              |
| `task-summary`          | 任务摘要     | `summary`, `timestamp`              |

### Subagent Transcripts

**Location:** `<session-uuid>/subagents/agent-<agentId>.jsonl` **Metadata:**
`agent-<agentId>.meta.json` → `{agentType, description, worktreePath?}`

子 agent 消息带 `isSidechain: true` 和 `agentId` 字段。Dream 可读取它们，但 Pi sessions 优先。

### Useful Grep Patterns

```bash
# 用户提示
python3 - <<'PY'
import sys, json
for l in open('session.jsonl', errors='ignore'):
    obj = json.loads(l)
    if obj.get('type') == 'user':
        content = obj.get('message', {}).get('content', '')
        if isinstance(content, str) and len(content) > 10 and not content.startswith('<'):
            print(content[:300])
PY

# 工具调用
python3 - <<'PY'
import json
for l in open('session.jsonl', errors='ignore'):
    obj = json.loads(l)
    blocks = obj.get('message', {}).get('content', [])
    if not isinstance(blocks, list):
        continue
    for block in blocks:
        if isinstance(block, dict) and block.get('type') == 'tool_use':
            print(block.get('name', '?'), block.get('input', {}))
PY

# 错误相关行
rg -i "error|exception|failed|traceback" session.jsonl

# 会话标题
rg '"ai-title"|"custom-title"' session.jsonl
```

### Session Discovery

```bash
# 最近 Claude Code sessions
find ~/.claude/projects -maxdepth 2 -name "*.jsonl" -not -path "*/subagents/*" -mtime -7 -exec ls -lhS {} + | head -20

# 最近活跃项目
find ~/.claude/projects -maxdepth 2 -name "*.jsonl" -not -path "*/subagents/*" -mtime -7 \
  | sed 's|/[^/]*\.jsonl$||' | sort -u
```

---

## Codex CLI JSONL

**Location:** `~/.codex/sessions/YYYY/MM/DD/rollout-<ISO-timestamp>-<session-uuid>.jsonl`

### Event Structure

每行有 `timestamp`、`type` 和对应 payload：

```json
{"timestamp": "2026-04-04T22:15:00Z", "type": "session_meta"}
{"timestamp": "2026-04-04T22:15:01Z", "type": "response_item"}
{"timestamp": "2026-04-04T22:15:02Z", "type": "event_msg"}
{"timestamp": "2026-04-04T22:15:03Z", "type": "turn_context"}
```

### Event Types

**`session_meta`** — 文件头：

- `payload.id`: Session UUID
- `payload.cwd`: 工作目录
- `payload.cli_version`: CLI 版本
- `payload.originator`: `codex_cli_rs` 或 `codex_exec`
- `payload.model_provider`: 模型提供方
- `payload.base_instructions`: system prompt 文本
- `payload.git`: git 上下文

**`response_item`** — 对话 turn：

- `payload.type`: `message` / `function_call` / `function_call_output` / `reasoning`
- 消息：`payload.role` = `developer` / `user` / `assistant`
- 工具调用：`payload.name`, `payload.arguments`, `payload.call_id`
- 工具结果：`payload.call_id`, `payload.output`
- reasoning：`payload.encrypted_content`，不可读

**`event_msg`** — 生命周期事件：`task_started`, `task_complete`, `token_count`, `user_message`,
`agent_message`

**`turn_context`** — turn 元信息：`cwd`, `date`, `approval_policy`, `sandbox_policy`, `model_name`

### Useful Grep Patterns

```bash
# 用户消息
rg '"type":"event_msg"' rollout.jsonl | rg '"user_message"'

# 工具调用
rg '"function_call"' rollout.jsonl | rg -v '"function_call_output"'

# 工具结果
rg '"function_call_output"' rollout.jsonl

# 助手文本
rg '"type":"response_item"' rollout.jsonl | rg '"output_text"'

# 会话元信息
rg '"type":"session_meta"' rollout.jsonl

# 最近 Codex sessions
find ~/.codex/sessions -name "rollout-*.jsonl" -mtime -7 -exec ls -lhS {} + | head -20
```

### Codex SQLite (Supplementary)

**`~/.codex/state_5.sqlite`** — thread index，常见字段：

- `id`, `title`, `model`, `cwd`, `git_branch`, `git_origin_url`
- `first_user_message`, `tokens_used`, `created_at`, `updated_at`

```bash
sqlite3 ~/.codex/state_5.sqlite "SELECT id, title, model, cwd, datetime(created_at, 'unixepoch') FROM threads ORDER BY created_at DESC LIMIT 20"
```

### Codex History (Supplementary)

**`~/.codex/history.jsonl`** — prompt log：

```json
{ "session_id": "uuid", "ts": 1712300000, "text": "user prompt text" }
```

---

## Cross-Format Comparison

| Feature          | Pi                                      | Claude Code                          | Codex                                    |
| ---------------- | --------------------------------------- | ------------------------------------ | ---------------------------------------- |
| Location         | `~/.pi/agent/sessions/**/*jsonl`        | `~/.claude/projects/*/<uuid>.jsonl`  | `~/.codex/sessions/YYYY/MM/DD/*.jsonl`   |
| Main role        | 主来源                                  | 辅助来源                             | 辅助来源                                 |
| Message format   | `type: message` + `message.*`           | `message.content` 字符串或数组       | `payload.content[].type`                 |
| Tool calls       | `message.toolName`, `toolCallId`        | `type: "tool_use"` in content array  | `type: "function_call"` as response_item |
| Tool results     | `message` 记录                          | `tool_result` message                | `function_call_output` response_item     |
| Reasoning        | 视模型和 Pi 版本而定                    | `type: "thinking"`                   | `type: "reasoning"` encrypted            |
| Session metadata | `session`, `session_info`, `compaction` | `ai-title`, `tag`, `pr-link` entries | `session_meta` + `turn_context`          |
| Subagents        | Pi 子会话 / subagent 会话目录           | Separate `subagents/` directory      | Client-specific                          |
| Index DB         | JSONL 文件树                            | JSONL only                           | SQLite `state_5.sqlite`                  |
