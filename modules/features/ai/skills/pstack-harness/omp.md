# pstack in omp

pstack skills use Cursor names. In omp, read this file once per session, then map each Cursor name with the tables below. If a Cursor field has no row, drop it and say so. Never pass a field or value that the `task` schema rejects.

## Tools

| Cursor | omp |
| --- | --- |
| `Task` | `task`. Batch is on by default: one call carries `{ context, tasks[] }`, one subagent per item. `context` is the shared background rendered into every spawn; it is required and never repeated per item. |
| `AskQuestion` | `ask`. Omit it under a full-autonomy grant. |
| Open a todolist | `todo`. |
| Run another pstack skill (`/name` or "the **name** skill") | `read skill://<name>`. When you tell the user to type it, write `/skill:<name>`. |
| `Grep`, `Glob` | `grep` and `find` always work for content and paths. Use `glob` only when the session lists it. |

## Spawning

| Cursor | omp |
| --- | --- |
| `subagent_type: generalPurpose` | Omit `agent`; the spawn uses the session default. |
| `readonly: true` | A read-only agent: `scout` for exploration, a reviewer agent for review. The `task` tool description lists both. |
| `readonly: false` | The default general worker agent. |
| `poteto-agent` | The pstack delegate agent, when the session lists one built from pstack's `agents/poteto-agent.md`. Otherwise use the default and say so. |
| `comment-sicko` | The pstack comment-review agent, when the session lists one built from pstack's `agents/comment-sicko.md`. Otherwise use the default and say so. |
| `model: <slug>` | **Not accepted.** `task` rejects a `model` field unless the agent is `seance`. See Models. |
| `environment: "cloud"` | Drop it. Subagents run in the current checkout. Isolation exists as `task.isolation.enabled`; while it is off, `isolated` is absent from the schema. |
| `environment: "local"` | Drop it; that is the only mode. |
| `cloud_base_branch: <b>` | Drop it, and tell the worker which branch or commit to check out in its brief. |
| `run_in_background: true` | Omit it. With `async.enabled` on, every spawn is a background job; with it off, the call blocks. There is no per-spawn switch either way. |
| `run_in_background: false` | Not expressible; wait for the result with `wait`. |
| `resume` | `write agent://<id>` to a finished agent. Its session is revived, so do not re-send the earlier context. |
| `file_attachments` | List the paths in the brief. |

Every item also requires `solutionSpace`: how open-ended the child's problem is, not how large. Bad: `fix the bug`. Good: `one fix: null deref in parseHeader, cause known`. Batch calls also need a non-empty shared `context`.

## Models

There is no `~/.cursor/rules/pstack-models.mdc` here. A pstack role maps to an agent type, never to a model slug.

- The `task` tool description lists the agents this session can spawn. That list is the only source of truth; read it before naming one.
- Pick the agent whose description matches the role: review work to a reviewer agent, exploration to `scout`, implementation to the default worker.
- A role naming a list of models (arena runners, interrogate reviewers, architect runners, cross-judge pool) means one spawn per entry, on distinct model families where the list allows.
- `inherit-parent` or `auto` means omit `agent`, so the spawn runs on the session default.
- Cursor slugs such as `claude-opus-5-5-xhigh`, `grok-4.7-xhigh-fast`, and `gpt-*` are not omp selectors. Translate the role to an agent first.
- No agent matches the role: spawn the default and state which role degraded. A refused agent name is an error, not a hint to retry another name.

Role values live in nix, not in a rule file: `modules/features/ai/agents/default.nix` reads `modelRoles` from `modules/features/ai/omp/config.yml` and generates the agent definitions.

## setup-pstack

Nothing to configure at runtime. Do not write a rule file; the agent list in the `task` tool description is authoritative. Report that and stop.

## Paths

| Cursor | omp |
| --- | --- |
| `.cursor/skills/`, `~/.cursor/skills/` | `.omp/skills/` (project), `~/.omp/agent/skills/` (user), `~/.agents/skills/` (shared, where pstack is installed) |
| `~/.cursor/plugins/`, `.cursor-plugin/plugin.json` | pstack is installed as plain skills under `~/.agents/skills/`; there is no plugin manifest to read |
| `.cursor/rules/*.mdc`, always-applied rules | omp loads standing instructions from `AGENTS.md` files (`~/.omp/agent/AGENTS.md` user, `.omp/AGENTS.md` project), which nix manages. Do not write one for pstack. |
| `https://github.com/cursor/plugins/blob/main/pstack/<path>` | `skill://<name>/<path>` when the file is inside that skill, otherwise say the URL is unavailable offline and continue without it. |
| Transcripts in `~/.cursor/projects/<slug>/agent-transcripts/` | `~/.omp/agent/sessions/<slug>/*.jsonl`, newest directly inside that folder. `history://<id>` renders a subagent's transcript. |

## Cursor-only features

omp has no Cursor Automations, Bugbot, or cloud agents. When a step needs one, put one line in your reply, `Skipped in omp: <step>. <reason>.`, then go on. Do not stop, ask, or retry.

| Cursor | omp |
| --- | --- |
| Cursor Automations: routines, `update_state` routine calls, `api2.cursor.sh/automations` webhooks, routine wakes, `SendToUser` secret requests | Skip with the line. |
| Bugbot | Triage bugbot comments as ordinary review threads with `gh`. Skip a step that starts, waits for, or configures Bugbot when the PR has no Bugbot check or comment. |
| Cursor cloud agents | Nothing to map. Run locally and skip any step that needs the cloud agent itself, such as its dashboard status or its own machine. |
| A built-in PR tool | Use the forge command the step already gives, such as `gh pr create`. That is not a skip, so write no line. |
