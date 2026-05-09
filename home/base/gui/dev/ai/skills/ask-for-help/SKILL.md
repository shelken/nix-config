---
name: ask-for-help
description:
  Use Codex CLI to ask a stronger model for help. Read this skill when you repeatedly fail on a hard
  problem and cannot solve it, or when user asks you to "ask a stronger model" or "ask Codex for
  help".
---

# ask-for-help

Ask questions and get help through `codex cli`.

## Decisions

- If the first attempt fails for various reasons, try at most one more time, then stop and report
  the issue to user.
- When `confirming model`, if no model is stronger than current model, stop and explain to user.
- After receiving analysis from model, evaluate suggestions and identified issues.

## how

First determine current model tier. When stuck on an unsolved problem, ask a model at least as
advanced as current one. For example, if current model is 5.4, choose 5.4 or higher, such as 5.5.

### Confirm model

```bash
# Exclude pro/mini models, select bottom 10
pi --list-models | grep -iP "openai(?\!\s*/)\s*gpt" | grep -vE '(pro|mini|nano)' | tail -10
```

### Ask

```bash
codex --ask-for-approval never --model {model} exec --ephemeral --sandbox danger-full-access \
--ignore-user-config --skip-git-repo-check -C {cwd} -c project_doc_max_bytes=0 \
-c 'skills.enabled=false' \
-c 'model_reasoning_effort="{low,medium,high}"' - <<'EOF'
{put context here}
EOF
```

Example:

```bash
codex --ask-for-approval never --model gpt-5.4-mini exec --ephemeral --sandbox danger-full-access \
--ignore-user-config --skip-git-repo-check -C /tmp -c project_doc_max_bytes=0 \
-c 'skills.enabled=false' \
-c 'model_reasoning_effort="medium"' - <<'EOF'
Read ~/.codex/AGENTS.md and only answer what MBTI is
EOF
```

**Prompting tips:**

- Provide enough context: requirements, relevant code, related files, risk points, **pitfalls
  already hit**, and **attempts already made**.
- Ask model to inspect code, identify real problem, and give suggestions.
