---
name: agy-review
description: Adversarially review anything - a plan, design, code change, piece of writing, decision, argument, config, or idea - with the `agy` (Antigravity) CLI. A fast second opinion from an independent model that pokes holes in whatever you give it - questionable assumptions, flaws, risks, gaps, failure modes, and a SHIP/REVISE/RETHINK verdict. Use when you want to red-team / stress-test / sanity-check / critique something, "poke holes in this", "what am I missing", "what's wrong with this", "get a second opinion", "review this with agy", or harden it before committing. Pairs with brainstorming and writing-plans.
disable-model-invocation: true
---

# agy-review

Run anything past the `agy` CLI for a quick adversarial critique — questionable assumptions, flaws, risks, gaps, failure modes, and a SHIP/REVISE/RETHINK verdict — from a second, independent model. Use it to harden a thing *before* you commit to it, not to replace your own judgment.

It reviews **whatever you give it** — a plan or design is just one case. Also: a code change, an essay or doc, a product/architecture decision, an argument or pitch, a config, a prompt, a name, an idea. Raw code, numbered specs, prose — all fine.

## What to review (arguments)

Invoked as `/agy-review [text or file to review]`. Interpret the argument — `$ARGUMENTS` — as *what to critique*:

- a **file path** → review its contents (pass it with `-f`);
- **pasted text** or an inline description → review that;
- **nothing** → review the most relevant artifact in the current context (e.g. the plan, draft, or decision you just produced), and state what you picked.

## How to run it

One script does everything: `scripts/agy-review.sh`. Give it the content via stdin, a file, or an argument; add `-c` to say what the thing is so the critique is on-target.

```bash
# pipe content in (most common when reviewing your own draft)
printf '%s\n' "$THING" | scripts/agy-review.sh -

# from a file, with context about what it is / the goal
scripts/agy-review.sh -f design.md -c "B2B SaaS onboarding flow; must ship this sprint"
scripts/agy-review.sh -f rate-limiter.md -c "Node/Express service behind a load balancer"
```

It prints the critique to stdout and exits `0`. Read the bullets, then weigh them — adopt the real ones, dismiss the off-base ones, and tell the user which is which.

## Model

Defaults to **`gemini-3.6-flash-high`** (Gemini 3.6 Flash in its highest thinking mode), per preference. Override with `AGY_REVIEW_MODEL="<name>"` (see `agy models` for exact strings) or `-m`.

## Reading the result

The last line is `VERDICT: SHIP / REVISE / RETHINK - <biggest issue>`. Treat it as input, not a verdict you must obey:

- **SHIP** — no blocking issues found; still skim the bullets.
- **REVISE** — fix the flagged issues, then proceed.
- **RETHINK** — it may be fundamentally off; reconsider before committing.

Always reconcile the critique with your own reasoning and the actual context. A second model is good at catching blind spots and bad at knowing your context — keep what's true, drop what isn't, and tell the user which is which.

## Notes

- Needs the `agy` CLI on `PATH` (`agy --version`). Missing → exit `2`.
- The script runs `agy` from a throwaway empty directory, so it never reads, edits, or crawls your repo — it just asks `agy` a question and prints the answer.
- Reviews typically run in ~5–20s.
- Env knobs: `AGY_REVIEW_MODEL` · `AGY_PRINT_TIMEOUT` (2m) · `AGY_HARD_TIMEOUT` (150s).
- Exit codes: `0` critique printed · `1` usage error · `2` `agy` not found or returned nothing.
