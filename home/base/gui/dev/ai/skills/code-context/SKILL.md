---
name: code-context
description:
  在写代码前补齐上下文并输出可执行结论。只要用户提到“先理解仓库”“查官方
  API”“找真实示例”“做升级迁移评估”“排查实践写法”，都应触发此 skill，即使用户没明确说
  code-context。固定流程：先本地，再按需使用 DeepWiki、Context7、Exa。
---

# Code Context

## Workflow

1. 先查本地：依赖版本、现有实现、项目文档。
2. 选一个主来源：

- 仓库结构/模块关系：DeepWiki
- API/版本行为：Context7
- 真实示例/实践：Exa

3. 只在必要时补一个次来源，避免信息噪音。
4. 输出统一结论：可执行建议 + 版本前提 + 来源链接。

## Command Setup

```bash
# Context7 CLI
command -v ctx7 >/dev/null 2>&1 || npm install -g ctx7@latest

# DeepWiki CLI
command -v deepwiki >/dev/null 2>&1 || npm install -g @seflless/deepwiki

# Exa API Key（官方 Search API）
: "${EXA_API_KEY:?请先 export EXA_API_KEY=<your_key>}"
```

## Quick Reference

### Context7

```bash
ctx7 library <name> <query>
ctx7 docs <libraryId> <query>
```

### DeepWiki

```bash
deepwiki toc <owner/repo>
deepwiki wiki <owner/repo>
deepwiki ask <owner/repo> "<question>"
```

### Exa

```bash
curl -sS https://api.exa.ai/search \
  -H 'Content-Type: application/json' \
  -H "x-api-key: $EXA_API_KEY" \
  -d '{
    "query": "TypeScript Next.js 14 server action error handling example",
    "type": "auto",
    "numResults": 5,
    "contents": { "highlights": true }
  }' \
| jq '.results[] | {title, url, highlights: (.highlights // [])}'
```

## Query Rules

- 查询必须带语言/框架/版本，例如 `TypeScript React 19`。
- 有具体标识符时写全：函数名、配置项、报错原文。
- DeepWiki 先 `toc` 再 `ask`，先结构后细节。

## Output Format

```markdown
## 结论

- 可直接执行的建议

## 版本前提

- 适用版本 / 不兼容点

## 来源

- URL 1
- URL 2
```

---

> Sources
>
> - https://github.com/upstash/context7
> - https://github.com/seflless/deepwiki
> - https://www.deepwiki.sh/
> - https://docs.exa.ai/reference/search
> - https://github.com/exa-labs/openapi-spec
