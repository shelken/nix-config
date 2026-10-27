# pstack in omp

pstack skills use Cursor names. In omp, read this file once per session, then map each Cursor name with the tables below. If a Cursor field has no row, drop it and say so. Never pass a field or value that the `task` schema rejects.

## Tools

| Cursor | omp |
| --- | --- |
| `Task` | `task`. Batch is on by default: one call carries `{ context, tasks[] }`, one subagent per item. `context` is the shared background rendered into every spawn; it is required and never repeated per item. |
| `AskQuestion` | `ask`. Omit it under a full-autonomy grant. |
| Open a todolist | `todo`. |
| Run another pstack skill (`/name` or "the **name** skill") | `read skill://<name>`. When you tell the user to type it, write `/skill:<name>`. |
| `Grep`, `Glob` | `grep`, `glob`, `find`. `glob` is disabled in this config; use `find` for paths and `grep` for content. |

## Spawning

| Cursor | omp |
| --- | --- |
| `subagent_type: generalPurpose` | Omit `agent`; the default is `task`. |
| `readonly: true` | `agent: scout` (READ-ONLY; it cannot edit). For a read-only reviewer use `reviewer`, `reviewer-general`, `reviewer-ds`, `reviewer-glm`, `reviewer-gemini`, or `reviewer-gpt`. |
| `readonly: false` | `agent: task`. |
| `poteto-agent` | `agent: poteto` (from the pstack agent set). |
| `comment-sicko` | `agent: comment-sicko`. |
| `model: <slug>` | **Not accepted.** `task` rejects a `model` field unless the agent is `seance`. Pick the `agent` whose frontmatter pins the model; the role table below names them. Never invent a slug. |
| `environment: "cloud"` | Drop it. Subagents run in the current checkout. Isolation exists as `task.isolation.enabled` but is off in this config. |
| `environment: "local"` | Drop it; that is the only mode. |
| `cloud_base_branch: <b>` | Drop it, and tell the worker which branch or commit to check out in its brief. |
| `run_in_background: true` | Omit it; `async.enabled` is on, so every spawn is a background job. |
| `run_in_background: false` | Not expressible; there is no per-spawn blocking switch. Wait for the result with `wait`. |
| `resume` | `write agent://<id>` to a finished agent. Its session is revived, so do not re-send the earlier context. |
| `file_attachments` | List the paths in the brief. |

Every item also requires `solutionSpace`: how open-ended the child's problem is, not how large. Bad: `fix the bug`. Good: `one fix: null deref in parseHeader, cause known`. Batch calls also need a non-empty shared `context`.

## Models

There is no `~/.cursor/rules/pstack-models.mdc` here. Role to agent:

| pstack role | agent |
| --- | --- |
| `swarm workers`, `feature`, `refactoring`, `bug-fix`, `perf-issue`, `hillclimb`, `how explorer`, `why investigators`, `reflect tooling` | `pstack-worker` |
| `judgment and prose`, `hardest tasks`, `how explainer`, `why synthesizer`, `architect runners` | `pstack-judgment` |
| `interrogate reviewers`, `arena runners`, `arena cross-judge pool` | one agent per entry: `reviewer-general` (judgment), `reviewer-gpt`, `reviewer-ds`, `reviewer-glm`, `reviewer-gemini`. A list value means one spawn per entry. |
| `reflect judgment, divergent, synthesizer` | `pstack-judgment` |
| `inherit-parent`, `auto` | Omit `agent` so the spawn uses the default (`task`). |

Cursor slugs such as `claude-opus-5-5-xhigh`, `grok-4.7-xhigh-fast`, and `gpt-*` have no omp equivalent at all: `task` rejects `model` for every agent except `seance`. Translate the slug to a role above first, then spawn that agent. Never pass the slug, and never retry a rejected slug with another spelling.

A refused agent name is an error, not a hint to retry with another name. Spawn with the default `task` and say which role degraded.

## setup-pstack

There is nothing to configure at runtime. Roles live in nix (`modules/features/ai/agents/default.nix` reads `modelRoles`). Do not write a rule file; report that the role table above is authoritative and stop.

## Paths

| Cursor | omp |
| --- | --- |
| `.cursor/skills/`, `~/.cursor/skills/` | `.omp/skills/` (project), `~/.omp/agent/skills/` (user), `~/.agents/skills/` (shared, where pstack is installed) |
| `~/.cursor/plugins/`, `.cursor-plugin/plugin.json` | pstack is installed as plain skills under `~/.agents/skills/`; there is no plugin manifest to read |
| `.cursor/rules/*.mdc`, always-applied rules | `~/.omp/agent/RULES.md` (sticky, loaded every request) or `.omp/rules/*.md` (project). Do not write either for pstack; the role table above replaces the model rule. |
| `https://github.com/cursor/plugins/blob/main/pstack/<path>` | `skill://<name>/<path>` when the file is inside that skill, otherwise say the URL is unavailable offline and continue without it. |
| Transcripts in `~/.cursor/projects/<slug>/agent-transcripts/` | `~/.omp/agent/sessions/<slug>/*.jsonl`, newest directly inside that folder. `history://<id>` renders a subagent's transcript. |

## Cursor-only features

omp has no Cursor Automations, Bugbot, or cloud agents. When a step needs one, put one line in your reply, `Skipped in omp: <step>. <reason>.`, then go on. Do not stop, ask, or retry.

| Cursor | omp |
| --- | --- |
| Cursor Automations: routines, `update_state` routine calls, `api2.cursor.sh/automations` webhooks, routine wakes, `SendToUser` secret requests | Skip with the line. The `automate-me` and `make-bot-ui` skills are excluded from this install for that reason. |
| Bugbot | Triage bugbot comments as ordinary review threads with `gh`. Skip a step that starts, waits for, or configures Bugbot when the PR has no Bugbot check or comment. |
| Cursor cloud agents | Nothing to map. Run locally and skip any step that needs the cloud agent itself, such as its dashboard status or its own machine. |
| A built-in PR tool | Use the forge command the step already gives, such as `gh pr create`. That is not a skip, so write no line. |
