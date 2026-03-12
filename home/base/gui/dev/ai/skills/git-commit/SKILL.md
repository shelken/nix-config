---
name: git-commit
description:
  当用户说"帮我提交"、"commit"、"提交一下"时使用此 skill。只约束提交信息的风格，不干预提交范围。
---

# Git Commit 风格规范

## 格式

```
<emoji> <type>(<scope>): <title>

<body>
```

## 规则

- 使用 `conventional commits` 格式
- 标题和正文均使用**中文**
- 标题开头加合适的 Emoji
- 标题限制在 50 字符以内，末尾不加标点
- 正文仅在能补充标题之外的有用信息时才写，否则省略
- 正文每行限制在 72 字符以内
- 标题与正文之间用空行分隔

## 常用 type 与 Emoji

| type     | emoji | 含义           |
| -------- | ----- | -------------- |
| feat     | ✨    | 新功能         |
| fix      | 🐛    | 修复 bug       |
| refactor | ♻️    | 重构           |
| chore    | 🔧    | 构建/工具/依赖 |
| docs     | 📝    | 文档           |
| style    | 🎨    | 格式/代码风格  |
| test     | ✅    | 测试           |
| perf     | ⚡    | 性能优化       |
| ci       | 👷    | CI/CD          |
| revert   | ⏪    | 回滚           |

## 示例

```
✨ feat(auth): 添加 JWT 刷新令牌支持

- 新增 refresh_token 字段到响应体
- 令牌有效期从 1h 延长至 7d
```

```
🐛 fix(db): 修复并发写入时的死锁问题
```
