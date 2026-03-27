# 搜索说明

搜索阶段只负责拿搜索结果，不负责抓具体网页正文。

## 使用什么

优先用 `opencli`，因为它走用户真实浏览器会话。

## 强依赖

- `opencli`
- 可用的浏览器连接：`OPENCLI_CDP_ENDPOINT="http://127.0.0.1:9333"`

## 步骤

1. 先确认 `opencli` 支持哪些站点或搜索命令：

例如：

```bash
OPENCLI_CDP_ENDPOINT="http://127.0.0.1:9333" opencli list | grep -A12 -E "google|grok|xiaohongshu|bilibili|twitter"
```

2. 选最贴近目标站点的搜索入口，优先真实站内搜索或 Google。

3. 执行搜索时，`-f md` 必须放在命令最后。

## 常用

```bash
OPENCLI_CDP_ENDPOINT="http://127.0.0.1:9333" opencli google search "[关键词]" -f md
```

```bash
OPENCLI_CDP_ENDPOINT="http://127.0.0.1:9333" opencli twitter search "[关键词]" -f md
```

```bash
OPENCLI_CDP_ENDPOINT="http://127.0.0.1:9333" opencli xiaohongshu search "[关键词]" -f md
```
