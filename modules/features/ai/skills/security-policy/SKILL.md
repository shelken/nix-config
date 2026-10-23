---
name: security-policy
description: 安全规则：敏感信息的读取与暴露，sudo 命令。
disable-model-invocation: true
---

## 敏感信息

- 密码等敏感值无需出现在对话中
- 读取密码、密钥、Token 或凭据内容前，先取得用户允许

## 提权

- 默认不执行 sudo 相关命令
