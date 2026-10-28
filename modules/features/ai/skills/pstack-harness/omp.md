# pstack in omp

pstack skills use Cursor names. In omp, read this file once per session, then map each Cursor name with the tables below. If a Cursor field has no row, drop it and say so. Never pass a field or value that the `task` schema rejects.

## Tools

| Cursor | omp |
| --- | --- |
| `Task` | `task`. Batch is on by default: one call carries `{ context, tasks[] }`, one subagent per item. `context` is the shared background rendered into every spawn; it is required and never repeated per item. |
| `AskQuestion` | `ask`. Omit it under a full-autonomy grant. |
| Open a todolist | `todo`. |
| Run another pstack skill (`/name` or "the **name** skill") | `read skill://<name>`. When you tell the user to type it, write `/skill:<name>`. |
| `Grep`, `Glob` | Use the session search tools (`grep`, `find`); `glob` works only when the session lists it. |

## Spawning

| Cursor | omp |
| --- | --- |
| `subagent_type: generalPurpose` | Omit `agent`; the spawn uses the session default. |
| `readonly: true` | A read-only agent: `scout` for exploration, a reviewer agent for review. The `task` tool description lists both. |
| `readonly: false` | The default general worker agent. |
| `poteto-agent` | `agent: "poteto-agent"`. Nix generates it from pstack's `agents/poteto-agent.md`; it models `@task` and its first act is reading `~/.agents/skills/poteto-mode/SKILL.md`. Resume an existing one with `write agent://<id>` rather than spawning a sibling. |
| `comment-sicko` | `agent: "comment-sicko"`. Nix generates it from pstack's `agents/comment-sicko.md` as a read-only comment reviewer; it reports `MUST KILL` targets and never edits code. The `no-comments` skill spells the type `"Comment Sicko"`; that is the upstream display name, and the agent name here is the lowercase slug. |
| `subagent_type: "Comment Sicko"` | `agent: "comment-sicko"`. Same agent, lowercase slug; omp matches agent names case-sensitively and only the slug exists. |
| `model: <slug>` | **Not accepted.** `task` rejects a `model` field unless the agent is `seance`. See Models. |
| `environment: "cloud"` | Drop it. Subagents run in the current checkout. |
| `environment: "local"` | Drop it; that is the only mode. |
| `cloud_base_branch: <b>` | Drop it, and tell the worker which branch or commit to check out in its brief. |
| `run_in_background: true` | Omit it. With `async.enabled` on (the default), spawns run in the background and the call returns immediately; with it off, the call blocks and returns results inline. |
| `run_in_background: false` | Not expressible; wait for the result with `wait`. |
| `resume` | `write agent://<id>` to a finished agent. Its session is revived, so do not re-send the earlier context. |
| `file_attachments` | List the paths in the brief. |

Every item also requires `solutionSpace`: how open-ended the child's problem is, not how large. Bad: `fix the bug`. Good: `one fix: null deref in parseHeader, cause known`. Batch calls also need a non-empty shared `context`.

## Models

No pstack skill selects a model here. Every slug, alias, and model rule file in the skill text is dead weight.

- Pick the agent whose description matches the role: review to a reviewer agent, exploration to `scout`, implementation to the default worker.
- Ignore model lists in pstack skills and upstream rule files.
- The `task` tool description lists the spawnable agents.
- When no agent matches a requested role, spawn the default worker and state which role degraded.

The reviewer panel is one seat per distinct model among the `reviewer-<variant>` agents in the `task` tool description. Resolve each variant's model via `omp config get modelRoles --json`. When two variants resolve to the same model, spawn one and state which variant you dropped.

`judge` is an independent agent bound to the `@judge` role in `config.yml`. It scores options and does not review code.

## Adversarial review panels

`/interrogate` and `/arena` fan out across model families. The upstream tables of slugs and the `interrogate reviewers` / `arena runners` lines from `~/.cursor/rules/pstack-models.mdc` have no counterpart here: the panel is the reviewer set, and the mapping from Reviewer A/B/C/D to a concrete agent lives in the `tasks[]` batch, not in a rule file.

| Cursor | omp |
| --- | --- |
| One `generalPurpose` spawn per configured reviewer, `readonly: true` | One `tasks[]` item per panel member, `agent: "reviewer-<variant>"`. All items share one `context` and the same task text and rubric; the reviewer agent's own prompt owns the output schema. |
| Reviewer A/B/C/D labels paired with a slug | One `tasks[]` item per seat in the reviewer panel. Drop a seat only when its model is unavailable or duplicates another seat's model; say which one dropped. |
| `arena runners` — N candidates on different models | Same panel as runners, one item each: `agent: "reviewer-<variant>"` for read-only design candidates, `agent: "poteto-agent"` for the seat that must write. Give every candidate its own output path. |
| `arena cross-judge pool` | `agent: "judge"`. That agent is the adjudicator: it scores candidates criterion by criterion against the rubric and names a base. It is bound to the `@judge` role, takes paths to the candidates, and never edits. Do not substitute a `reviewer-<variant>` here: reviewers hunt bugs in a diff, they do not rank options. |
| Lead judgment: the parent reads every result and decides | Stay in the main session. Fan out, then synthesize here. Do not delegate the verdict to a member of the panel it is judging; the `judge` agent is the only exception, and only when it ran on a family that produced no candidate. |

Reviewers never edit. A panel item that needs to prove a candidate builds belongs in the candidate's own worktree, and the reviewer reads the diff.

## Quick exploration and adjudication

| Cursor | omp |
| --- | --- |
| `/how` explorer (`readonly: true`) | `agent: "scout"`. Read-only exploration; give it one exploration angle and the symbol or call path, and ask for a cited trace, not a fix. |
| `/why` investigator (`readonly: false`) | `agent: "task"`. The upstream mode exists so MCP tools stay available, and `scout` cannot carry them. Keep the no-write posture in the brief instead; that is the posture, not the sandbox. |
| Lead reviewer / adjudicator | The main session, or one reviewer variant when the verdict needs a stronger reasoning model than the session's own context; pick the variant whose `@reviewer-<variant>` role resolves to that model. |

## Cursor-only dependencies

| Upstream dependency | omp |
| --- | --- |
| `deslop` (from `cursor-team-kit`) | Apply the **unslop** skill to every prose surface, then run `agent: "comment-sicko"` over the diff for the comment layer. The `no-comments` skill orchestrates this workflow. |
| `create-skill` (Cursor built-in) | Follow this repo's `writing-for-agents` skill. |
| `control-cli` (from `cursor-team-kit`) | Read `skill://control-cli` and follow its harness loop: prefer the repo's own test or demo harness, otherwise a temporary `tmux` or PTY harness under `/tmp`, one action at a time with a deterministic wait. Quote the captured screen, then delete the harness. |
| `control-ui` (from `cursor-team-kit`) | Use the `agent-browser` skill instead; it drives Chrome over CDP. Workflow: `agent-browser open <url>` → `agent-browser snapshot -i` (element refs) → `fill`/`click` by ref → `wait --load networkidle` → re-snapshot and assert. For a native app rather than a page, use `computer-use-best-practice` instead of a browser. |


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
