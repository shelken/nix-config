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
| `poteto-agent` | `spawn-subagent poteto-agent`. Nix generates the profile from pstack's `agents/poteto-agent.md`; it models `@task` and its first act is reading `~/.agents/skills/poteto-mode/SKILL.md`. Resume an existing pane with `spawn-subagent resume <pane-id>` rather than spawning a sibling. |
| `comment-sicko` | `spawn-subagent comment-sicko`. Nix generates the profile from pstack's `agents/comment-sicko.md` as a read-only comment reviewer; it reports `MUST KILL` targets and never edits code. The `no-comments` skill spells the type `"Comment Sicko"`; that is the upstream display name, and the profile name here is the lowercase slug. |
| `subagent_type: "Comment Sicko"` | `spawn-subagent comment-sicko`. Same profile, lowercase slug; the loader keys profiles by filename and only the slug exists. |
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

No pstack skill selects a model here. Every slug, alias, and model rule file in the skill text is dead weight.

- Model choice lives in the profile, not in the call. Pick the profile whose description matches the role: review to a reviewer profile, exploration to `scout`, implementation to the general worker.
- Every pstack model list, whether named in the skill or in a missing rule file, is not a model selector. Ignore the whole list, including any table of default slugs.
- `spawn-subagent list` prints every profile with its model, thinking level, tools, and description. That output is the only source of truth.
- No profile matches the role: dispatch the general worker and say which role degraded. Do not retry another name.

Nix generates one reviewer profile per entry in `reviewerVariants` (`modules/features/ai/agents/default.nix`), each bound to the `@reviewer-<variant>` role in `config.yml`. Never restate that set here: `spawn-subagent list` prints the profiles this machine has. A variant's model family is the provider its role resolves to in `config.yml`, so distinct names do not prove distinct families; check the resolved provider before counting a finding as cross-family agreement.

`judge` is a separate profile, not a reviewer variant: it is bound to the `@judge` role in `config.yml` and exists for scoring options, not for finding bugs. Role resolution happens at dispatch; the order and its fallbacks live in `modules/features/ai/skills/subagent-policy/spawn-subagent`.

## Adversarial review panels

`/interrogate` and `/arena` fan out across model families. The upstream tables of slugs and the `interrogate reviewers` / `arena runners` lines from `~/.cursor/rules/pstack-models.mdc` have no counterpart here: the panel is the reviewer set, and the Reviewer A/B/C/D to profile mapping lives in the batch manifest, not in a rule file.

| Cursor | pi |
| --- | --- |
| One `generalPurpose` spawn per configured reviewer, `readonly: true` | One entry in the `batch` manifest per panel member, named `reviewer-<variant>`. Every entry shares the same brief and rubric; the profile's prompt owns the output schema. |
| Reviewer A/B/C/D labels paired with a slug | One manifest entry per reviewer profile from `spawn-subagent list`, each on a distinct resolved family. Drop a member only when its provider is unavailable; say which one dropped. |
| `arena runners` — N candidates on different models | Same panel as runners, one manifest entry each, one profile per model family: `reviewer-<variant>` for read-only design candidates, `poteto-agent` for the seat that must write. Never run two candidates on the same family; when the brief needs more seats than families, say which family got a second seat. Give every candidate its own output path. |
| `arena cross-judge pool` | `spawn-subagent judge`. That profile is the adjudicator: it scores candidates criterion by criterion against the rubric and names a base. It is bound to the `@judge` role, takes paths to the candidates, and never edits; confirm in `config.yml` that the role resolves to a different family from the write seat. Do not substitute `reviewer-<variant>` here: reviewers hunt bugs in a diff, they do not rank options. |
| Lead judgment: the parent reads every result and decides | Stay in the main session and synthesize after the intercom results arrive. Do not delegate the verdict to a member of the panel it is judging; `judge` is the only exception, and only when it ran on a family that produced no candidate. |

Reviewers never edit. A panel item that needs to prove a candidate builds belongs in the candidate's own worktree, and the reviewer reads the diff.

## Quick exploration and adjudication

| Cursor | pi |
| --- | --- |
| `/how` explorer (`readonly: true`) | `scout`. Read-only exploration; give it one exploration angle and the symbol or call path, and ask for a cited trace, not a fix. |
| `/why` investigator (`readonly: false`) | The general worker profile. The upstream mode exists so MCP tools stay available, and `scout` cannot carry them. Keep the no-write posture in the brief instead. |
| Lead reviewer / adjudicator | The main session, or one reviewer profile when the verdict needs a stronger reasoning model than the session's own context; pick the profile whose `@reviewer-<variant>` role resolves to that model. |

## Cursor-only dependencies

| Upstream dependency | pi |
| --- | --- |
| `deslop` (from `cursor-team-kit`) | Apply the **unslop** skill to every prose surface, then run `comment-sicko` over the diff for the comment layer. The `no-comments` skill orchestrates this workflow. |
| `create-skill` (Cursor built-in) | Follow this repo's `writing-for-agents` skill. |
| `control-cli` (from `cursor-team-kit`) | Read `~/.agents/skills/control-cli/SKILL.md` and follow its harness loop: prefer the repo's own test or demo harness, otherwise a temporary `tmux` or PTY harness under `/tmp`, one action at a time with a deterministic wait. Quote the captured screen, then delete the harness. |
| `control-ui` (from `cursor-team-kit`) | Use the `agent-browser` skill instead; it drives Chrome over CDP. Workflow: `agent-browser open <url>` → `agent-browser snapshot -i` (element refs) → `fill`/`click` by ref → `wait --load networkidle` → re-snapshot and assert. For a native app rather than a page, use `computer-use-best-practice` instead of a browser. |

## setup-pstack

Nothing to configure at runtime. Do not write a rule file; `spawn-subagent list` is authoritative. Report that and stop.

## Paths

| Cursor | pi |
| --- | --- |
| `.cursor/skills/`, `~/.cursor/skills/` | `.pi/skills/` (project), `~/.pi/agent/skills/` (user), `~/.agents/skills/` (shared, where pstack is installed) |
| `~/.cursor/plugins/`, `.cursor-plugin/plugin.json` | pstack is installed as plain skills under `~/.agents/skills/`; there is no plugin manifest to read |
| `.cursor/rules/*.mdc`, always-applied rules | pi loads standing instructions from `AGENTS.md` (`~/.pi/agent/AGENTS.md` user, `.pi/AGENTS.md` project), which nix manages. Do not write one for pstack. |
| `https://github.com/cursor/plugins/blob/main/pstack/<path>` | `~/.agents/skills/<name>/<path>` when the file is inside that skill, otherwise say the URL is unavailable offline and continue without it. |
| Transcripts in `~/.cursor/projects/<slug>/agent-transcripts/` | `~/.pi/agent/sessions/<slug>/*.jsonl`, newest directly inside that folder. A subagent's own transcript lives under `~/.pi/agent-subagent/sessions/<slug>/*.jsonl`. |

## Cursor-only features

pi has no Cursor Automations, Bugbot, or cloud agents. When a step needs one, put one line in your reply, `Skipped in pi: <step>. <reason>.`, then go on. Do not stop, ask, or retry.

| Cursor | pi |
| --- | --- |
| Cursor Automations: routines, `update_state` routine calls, `api2.cursor.sh/automations` webhooks, routine wakes, `SendToUser` secret requests | Skip with the line. |
| Bugbot | Triage bugbot comments as ordinary review threads with `gh`. Skip a step that starts, waits for, or configures Bugbot when the PR has no Bugbot check or comment. |
| Cursor cloud agents | Nothing to map. Run locally and skip any step that needs the cloud agent itself, such as its dashboard status or its own machine. |
| A built-in PR tool | Use the forge command the step already gives, such as `gh pr create`. That is not a skip, so write no line. |
