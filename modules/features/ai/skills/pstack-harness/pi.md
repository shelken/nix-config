# pstack in pi

pstack skills use Cursor names. In pi, read this file once per session, then map each Cursor name with the tables below. If a Cursor field has no row, drop it and say so. Never pass a field or value that a tool schema rejects.

## Tools

| Cursor | pi |
| --- | --- |
| `Task` | `spawn-subagent`, one call per spawn; several spawns go through one `batch` manifest, never a loop. |
| `AskQuestion` | No ask tool. Write the question and the options in your reply. |
| Open a todolist | `todo`. |
| Run another pstack skill (`/name` or "the **name** skill") | `read ~/.agents/skills/<name>/SKILL.md`. When you tell the user to type it, write `/skill:<name>`. |
| `Grep`, `Glob` | `grep` and `find`; `ffgrep` and `fffind` when the session lists them. |

## Spawning

Run `spawn-subagent -h` once; its help owns the syntax, and this table only maps the Cursor fields.

| Cursor | pi |
| --- | --- |
| `subagent_type: generalPurpose` | The general worker profile. |
| `readonly: true` | A read-only profile: `scout` for exploration, a reviewer profile for review. |
| `readonly: false` | The general worker profile. |
| `poteto-agent` | The pstack delegate profile, when `spawn-subagent list` shows one built from pstack's `agents/poteto-agent.md`. Otherwise use the general worker and say so. |
| `comment-sicko` | The pstack comment-review profile, when the list shows one built from pstack's `agents/comment-sicko.md`. Otherwise use the general worker and say so. |
| `model: <slug>` | **Not accepted.** `spawn-subagent` takes a profile, and the profile's frontmatter pins `model` and `thinking`. See Models. |
| `environment: "cloud"` | Drop it. The agent runs in this checkout. |
| `environment: "local"` | Drop it; that is the only mode. |
| `cloud_base_branch: <b>` | Drop it, and put the branch or commit to check out in the brief. |
| `run_in_background: true` | Omit it. Dispatch returns a pane id after the health gate; the result arrives over intercom. |
| `run_in_background: false` | Not expressible. Dispatch, then end your turn and wait for the intercom result. |
| `resume` | `spawn-subagent resume <pane-id> -- <task>`; for a finished agent, message it over `intercom`. |
| `file_attachments` | List the paths in the brief. |

After a successful dispatch, **end your turn immediately**: no further tool calls, no sleep, no polling. The conclusion arrives over intercom and wakes you. This is the only reliable completion signal; panes report `idle` for the whole run.

Several spawns share one manifest file. A per-spawn model, `readonly`, or `cloud_base_branch` has no field; encode it in the task text instead.

```json
{
  "task": "shared brief",
  "agents": ["<profile>", { "profile": "<profile>", "slug": "extra-angle", "task": "additional instructions" }]
}
```

## Models

There is no `~/.cursor/rules/pstack-models.mdc` here. A pstack role maps to a profile, never to a model slug.

- `spawn-subagent list` prints every profile with its model, thinking level, tools, and description. That output is the only source of truth; run it before naming a profile.
- Pick the profile whose description matches the role: review work to a reviewer profile, exploration to `scout`, implementation to the general worker.
- A role naming a list of models (arena runners, interrogate reviewers, architect runners, cross-judge pool) means one spawn per entry, on distinct model families where the list allows.
- `inherit-parent` or `auto` means the profile inherits the parent model.
- Cursor slugs such as `claude-opus-5-5-xhigh`, `grok-4.7-xhigh-fast`, and `gpt-*` are not pi selectors. Translate the role to a profile first.
- No profile matches the role: dispatch the general worker and state which role degraded. A refused profile is an error, not a hint to retry another name.

Role values live in nix, not in a rule file: `modules/features/ai/agents/default.nix` reads `modelRoles` from `modules/features/ai/omp/config.yml` and generates the profile files.

## setup-pstack

Nothing to configure at runtime. Do not write a rule file; `spawn-subagent list` is authoritative. Report that and stop.

## Paths

| Cursor | pi |
| --- | --- |
| `.cursor/skills/`, `~/.cursor/skills/` | `.pi/skills/` (project), `~/.pi/agent/skills/` (user), `~/.agents/skills/` (shared, where pstack is installed) |
| `~/.cursor/plugins/`, `.cursor-plugin/plugin.json` | pstack is installed as plain skills under `~/.agents/skills/`; there is no plugin manifest to read |
| `.cursor/rules/*.mdc`, always-applied rules | pi loads standing instructions from `AGENTS.md` (`~/.pi/agent/AGENTS.md` user, `.pi/AGENTS.md` project), which nix manages. Do not write one for pstack. |
| `https://github.com/cursor/plugins/blob/main/pstack/<path>` | `~/.agents/skills/<name>/<path>` when the file is inside that skill, otherwise say the URL is unavailable offline and continue without it. |
| Transcripts in `~/.cursor/projects/<slug>/agent-transcripts/` | `~/.pi/agent/sessions/<slug>/*.jsonl`, newest directly inside that folder. A subagent's own transcript lives under `~/.pi/agent-subagent/sessions/`. |

## Cursor-only features

pi has no Cursor Automations, Bugbot, or cloud agents. When a step needs one, put one line in your reply, `Skipped in pi: <step>. <reason>.`, then go on. Do not stop, ask, or retry.

| Cursor | pi |
| --- | --- |
| Cursor Automations: routines, `update_state` routine calls, `api2.cursor.sh/automations` webhooks, routine wakes, `SendToUser` secret requests | Skip with the line. |
| Bugbot | Triage bugbot comments as ordinary review threads with `gh`. Skip a step that starts, waits for, or configures Bugbot when the PR has no Bugbot check or comment. |
| Cursor cloud agents | Nothing to map. Run locally and skip any step that needs the cloud agent itself, such as its dashboard status or its own machine. |
| A built-in PR tool | Use the forge command the step already gives, such as `gh pr create`. That is not a skip, so write no line. |
