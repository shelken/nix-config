---
name: code-context
description:
  使用于用户说「查官方API」「找真实示例」「新的文档」「最新api」「ctx7」;使用于需要任何库的当前最新文档，读取此 skill
disable-model-invocation: true
---

## 适用场景

获取库的当前最新文档，在编写代码、验证 API 签名或训练数据可能过时时使用

## CLI 准备

```bash
# Context7 CLI
command -v ctx7 >/dev/null 2>&1 || bun add -g ctx7@latest
```

## 查询顺序

```bash
ctx7 --help
ctx7 library <name> <query>           # Step 1: resolve library ID
ctx7 docs <libraryId> <query>         # Step 2: fetch docs
```

## 常见错误

- Library ID 必须以 `/` 开头，如 `/facebook/react`，不能写成 `facebook/react`
- 先执行 `ctx7 library` 获取有效 ID，再执行 `ctx7 docs`；`ctx7 docs react "hooks"` 会因 ID 无效而失败
