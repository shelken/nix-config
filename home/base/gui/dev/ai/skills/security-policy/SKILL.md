---
name: security-policy
description: 安全规则
disable-model-invocation: true
---

# 安全规则

## rules

- 密码等敏感值不需要出现在对话
- 未经用户允许，不读取密码、密钥、Token 或凭据内容
- 默认不应当执行 sudo 相关的命令
