---
name: postmortem
description: Read this skill when user explicitly asks to "write a postmortem".
---

## When phase completes or work wraps up

When a phase completes, or when preparing to end current work, write a postmortem if any of these
occurred:

- Wrong assumption
- Invalid exploration
- Tool usage error
- Avoidable retry
- Missing or incorrect verification flow
- Any issue worth avoiding next time

If there was no real incident, or only a small issue unlikely to repeat, do not force a postmortem.

## Location and naming

By default, store postmortem reports in `postmortems/` at project root.

File naming format must be:

`number-short-title.md`

Rules:

- Number is three-digit increasing sequence, such as `001`, `002`.
- Title uses lowercase English and hyphens.
- Title should briefly describe problem object and core mistake. No spaces, Chinese, or special
  characters.

Also maintain `postmortems/README.md` as postmortem index. Before coding, read
`postmortems/README.md`, then read related postmortems as needed.

## Postmortem report format

Use structure below:

```txt
# Title

**Date**: YYYY-MM-DD
**Impact**:
**Discovered by**:

## Problem
<!-- What happened and what was affected -->

## Symptoms
<!-- Minimal reproduction command + key error -->

## Root cause
<!-- Wrong assumption / actual constraint / missing checkpoint -->

## Fix
<!-- How recovery happened / correct future approach -->

## Prevention
<!-- Executable rules, no empty words -->

```

## README format

Keep concise.

```txt
# Postmortems

- [001 · Example title](./001-example.md)
- [002 · Example title](./002-example.md)
```
