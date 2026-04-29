---
name: ask-for-help
description:
  通过调用Codex
  Cli来获取更高智能的模型获取帮助，当你发现在某个困难问题上重复犯错，且无法解决时，或者用户让你「向更高智能的模型获取帮助」、「找Codex获取帮助」时
  读取这个技能，
---

# ask-for-help

通过调用 codex cli 来询问问题并获取帮助

## 决策

- 如果第一次因为各种问题没有解决，最多再尝试一次之后，停下来，向用户反馈问题
- `确认模型` 时，如果没有模型高于当前，停下来，向用户说明
- 得到模型的分析后，判断模型给的建议和指出的问题

## how

首先确定当前自己的模型等级，当遇到问题无法解决时，被提问的模型应该至少比自己先进，例如，当前为5.4，后面选择模型时应该向5.4及以上进行提问，例如 5.5

### 确认模型

```bash
# 排除 pro/mini 模型，选底部10个
pi --list-models | grep -iP "openai(?\!\s*/)\s*gpt" | grep -vE '(pro|mini|nano)' | tail -10
```

### 提问

```bash
codex --ask-for-approval never --model {model} exec --ephemeral --sandbox danger-full-access \
--ignore-user-config --skip-git-repo-check -C {cwd} -c project_doc_max_bytes=0 \
-c 'skills.enabled=false' \
-c 'model_reasoning_effort="{low,medium,high}"' - <<'EOF'
{这里放上下文}
EOF
```

例如

```bash
codex --ask-for-approval never --model gpt-5.4-mini exec --ephemeral --sandbox danger-full-access \
--ignore-user-config --skip-git-repo-check -C /tmp -c project_doc_max_bytes=0 \
-c 'skills.enabled=false' \
-c 'model_reasoning_effort="medium"' - <<'EOF'
阅读 ~/.codex/AGENTS.md ，只回答MBTI是什么
EOF
```

**提问技巧：**

- 上下文 给足需求、相关代码、相关文件、风险点、 **踩过哪些坑** 、 **做过哪些尝试**
- 让其看过代码之后 指出代码真正的问题所在 并 给出建议
