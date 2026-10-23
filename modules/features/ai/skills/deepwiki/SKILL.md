---
name: deepwiki
description: >
  Query any public GitHub repo's documentation via DeepWiki.
  Use when needing to understand a library, framework, or dependency.
  Triggers on "look up docs", "how does X work", "deepwiki".
---

# deepwiki

Query any public GitHub repo's docs from the terminal via DeepWiki. The `deepwiki` CLI is pre-installed via nix.

## Commands

| Command | Usage | Description |
|---------|-------|-------------|
| `toc`   | `deepwiki toc <owner/repo>` | Table of contents |
| `wiki`  | `deepwiki wiki <owner/repo>` | Full wiki content |
| `ask`   | `deepwiki ask <owner/repo> "<question>"` | AI-powered Q&A |
| `ask`   | `deepwiki ask <repo1> <repo2> "<question>"` | Multi-repo Q&A (max 10) |

## Flags

| Flag | Purpose |
|------|---------|
| `--json` | Raw JSON output (good for piping) |
| `-q, --quiet` | No spinners/progress |
| `--no-color` | Disable colors |

## Examples

```bash
# Understand a library's structure
deepwiki toc facebook/react

# Get full docs for reference
deepwiki wiki oven-sh/bun --json > bun-docs.json

# Ask a specific question
deepwiki ask anthropics/claude-code "How does the tool permission system work?"

# Cross-project question
deepwiki ask facebook/react vercel/next.js "How do server components work across these projects?"
```

## Tips

- Use `--json` when you need structured data to parse
- Use `toc` first to understand what docs exist, then `ask` for specifics
- Multi-repo `ask` is great for understanding how libraries interact
