---
name: papercuts
description: When you hit friction during work — a dead-end tool call, a broken link, a misleading doc, a footgun config, a missing helper — file it before moving on
---

When you hit friction during work — a dead-end tool call, a broken link, a
misleading doc, a footgun config, a missing helper — file it before moving on:

    papercuts add "<what you hit and what would have prevented it>" --tag <area>

Don't stop working; file it and push through. Severity: minor (default) for
annoyances, major for time sinks, blocker for hard walls. Run `papercuts schema`
once if you need the full contract. Attach `--cmd`, `--exit`, or `--stderr-file`
when filing tool failures; never feed raw environment dumps.
