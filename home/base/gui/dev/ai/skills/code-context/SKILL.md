---
name: code-context
description:
  使用于用户说「查官方API」「找真实示例」「新的文档」「最新api」「ctx7」;使用于需要任何库的当前最新文档，读取此 skill
---

## Command Setup

```bash
# Context7 CLI
command -v ctx7 >/dev/null 2>&1 || bun add -g ctx7@latest
```

## when to use

- 文档 — 获取任何库的当前最新文档，在编写代码、验证 API 签名或训练数据可能已过时时使用。

## Quick Reference

```bash
ctx7 --help 
ctx7 library <name> <query>           # Step 1: resolve library ID
ctx7 docs <libraryId> <query>         # Step 2: fetch docs
```

## Common Mistakes

- Library IDs require a `/` prefix — `/facebook/react` not `facebook/react`
- Always run `ctx7 library` first — `ctx7 docs react "hooks"` will fail without a valid ID
