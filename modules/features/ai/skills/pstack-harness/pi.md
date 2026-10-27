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

Nix generates one reviewer profile per entry in `reviewerVariants` (`modules/features/ai/agents/default.nix`), each bound to the `@reviewer-<variant>` role in `config.yml`. The panel is `reviewer-gpt`, `reviewer-ds`, `reviewer-glm`, `reviewer-gemini`, `reviewer-cc`: five families, so a finding two of them reach independently is cross-family agreement, not one model agreeing with itself.

## Adversarial review panels

`/interrogate` and `/arena` fan out across model families. The upstream tables of slugs and the `interrogate reviewers` / `arena runners` lines from `~/.cursor/rules/pstack-models.mdc` have no counterpart here: the panel is the reviewer set, and the Reviewer A/B/C/D to profile mapping lives in the batch manifest, not in a rule file.

| Cursor | pi |
| --- | --- |
| One `generalPurpose` spawn per configured reviewer, `readonly: true` | One entry in the `batch` manifest per panel member, named `reviewer-<variant>`. Every entry shares the same brief and rubric; the profile's prompt owns the output schema. |
| Reviewer A/B/C/D labels paired with a slug | Panel members `reviewer-gpt`, `reviewer-ds`, `reviewer-glm`, `reviewer-gemini`, `reviewer-cc`. Drop a member only when its provider is unavailable; say which one dropped. |
| `arena runners` — N candidates on different models | Same panel as runners: `poteto-agent` when a candidate must write (an arena candidate produces an artifact), `reviewer-<variant>` when the candidates are read-only designs. Give every candidate its own output path. |
| `arena cross-judge pool` | A judge from a different family than the base candidate: `reviewer-gpt` or `reviewer-cc` for synthesis, with the rubric and candidate paths in the brief. |
| Lead judgment: the parent reads every result and decides | Stay in the main session and synthesize after the intercom results arrive. Do not delegate the verdict to a member of the panel it is judging. |

Reviewers never edit. A panel item that needs to prove a candidate builds belongs in the candidate's own worktree, and the reviewer reads the diff.

## Quick exploration and adjudication

| Cursor | pi |
| --- | --- |
| `/how` explorer (`readonly: true`) | `scout`. Read-only exploration; give it one exploration angle and the symbol or call path, and ask for a cited trace, not a fix. |
| `/why` investigator (`readonly: false`) | The general worker profile. The upstream mode exists so MCP tools stay available, and `scout` cannot carry them. Keep the no-write posture in the brief instead. |
| Lead reviewer / adjudicator | The main session, or `reviewer-gpt` / `reviewer-cc` when the verdict needs a strong reasoning model rather than the session's own context. |

## Cursor-only dependencies

| Upstream dependency | pi |
| --- | --- |
| `deslop` (from `cursor-team-kit`) | Apply the **unslop** skill to every prose surface, then run `comment-sicko` over the diff for the comment layer. The `no-comments` skill orchestrates this and is installed. |
| `create-skill` (Cursor built-in) | Follow this repo's `writing-for-agents` skill. |
| `control-cli`, `control-ui` (from `cursor-team-kit`) | Run the real command in this checkout and quote what it printed; for UI work drive the actual app or a browser session. Build the script that proves it (`principle-build-the-lever`) so the next reviewer reruns it instead of retyping steps. |

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
