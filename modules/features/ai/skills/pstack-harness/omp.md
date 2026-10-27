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
| `poteto-agent` | `agent: "poteto-agent"`. Nix generates it from pstack's `agents/poteto-agent.md`; it models `@task` and its first act is reading `~/.agents/skills/poteto-mode/SKILL.md`. Resume an existing one with `write agent://<id>` rather than spawning a sibling. |
| `comment-sicko` | `agent: "comment-sicko"`. Nix generates it from pstack's `agents/comment-sicko.md` as a read-only comment reviewer; it reports `MUST KILL` targets and never edits code. The `no-comments` skill spells the type `"Comment Sicko"`; that is the upstream display name, and the agent name here is the lowercase slug. |
| `subagent_type: "Comment Sicko"` | `agent: "comment-sicko"`. Same agent, lowercase slug; omp matches agent names case-sensitively and only the slug exists. |
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

No pstack skill selects a model here. Every slug, alias, and model rule file in the skill text is dead weight.

- Model choice lives in the agent definition, not in the call. Pick the agent whose description matches the role: review to a reviewer agent, exploration to `scout`, implementation to the default worker.
- Every pstack model list, whether named in the skill or in a missing rule file, is not a model selector. Ignore the whole list, including any table of default slugs.
- The `task` tool description lists the agents this session can spawn. That list is the only source of truth.
- No agent matches the role: spawn the default and say which role degraded. Do not retry another name.

Nix generates one reviewer per entry in `reviewerVariants` (`modules/features/ai/agents/default.nix`), each bound to the `@reviewer-<variant>` role in `config.yml`. The panel is `reviewer-gpt`, `reviewer-ds`, `reviewer-glm`, `reviewer-gemini`, `reviewer-cc`: five families, so a finding two of them reach independently is cross-family agreement, not one model agreeing with itself.

## Adversarial review panels

`/interrogate` and `/arena` fan out across model families. The upstream tables of slugs and the `interrogate reviewers` / `arena runners` lines from `~/.cursor/rules/pstack-models.mdc` have no counterpart here: the panel is the reviewer set, and the mapping from Reviewer A/B/C/D to a concrete agent lives in the `tasks[]` batch, not in a rule file.

| Cursor | omp |
| --- | --- |
| One `generalPurpose` spawn per configured reviewer, `readonly: true` | One `tasks[]` item per panel member, `agent: "reviewer-<variant>"`. All items share one `context` and the same task text and rubric; the reviewer agent's own prompt owns the output schema. |
| Reviewer A/B/C/D labels paired with a slug | Panel members `reviewer-gpt`, `reviewer-ds`, `reviewer-glm`, `reviewer-gemini`, `reviewer-cc`. Drop a member only when its provider is unavailable; say which one dropped. |
| `arena runners` — N candidates on different models | Same panel as runners, one item each, `agent: "poteto-agent"` when the candidates need to write (an arena candidate produces an artifact), `reviewer-<variant>` when the candidates are read-only designs. Give every candidate its own output path. |
| `arena cross-judge pool` | A judge from a different family than the base candidate: `reviewer-gpt` or `reviewer-cc` for synthesis. `agent: "reviewer-<variant>"` with the rubric and candidate paths in the task. |
| Lead judgment: the parent reads every result and decides | Stay in the main session. Fan out, then synthesize here. Do not delegate the verdict to a member of the panel it is judging. |

Reviewers never edit. A panel item that needs to prove a candidate builds belongs in the candidate's own worktree, and the reviewer reads the diff.

## Quick exploration and adjudication

| Cursor | omp |
| --- | --- |
| `/how` explorer (`readonly: true`) | `agent: "scout"`. Read-only exploration; give it one exploration angle and the symbol or call path, and ask for a cited trace, not a fix. |
| `/why` investigator (`readonly: false`) | `agent: "task"`. The upstream mode exists so MCP tools stay available, and `scout` cannot carry them. Keep the no-write posture in the brief instead; that is the posture, not the sandbox. |
| Lead reviewer / adjudicator | The main session, or `reviewer-gpt` / `reviewer-cc` when the verdict needs a strong reasoning model rather than the session's own context. |

## Cursor-only dependencies

| Upstream dependency | omp |
| --- | --- |
| `deslop` (from `cursor-team-kit`) | Apply the **unslop** skill to every prose surface, then run `agent: "comment-sicko"` over the diff for the comment layer. The `no-comments` skill orchestrates this and is installed. |
| `create-skill` (Cursor built-in) | Follow this repo's `writing-for-agents` skill. |
| `control-cli`, `control-ui` (from `cursor-team-kit`) | Run the real command in this checkout and quote what it printed; for UI work drive the actual app or a browser session. Build the script that proves it (`principle-build-the-lever`) so the next reviewer reruns it instead of retyping steps. |


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
