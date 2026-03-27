# 抓网页说明

抓取阶段只负责获取某个具体 URL 的正文

## 使用什么

- 主方案：`npx defuddle parse [url]`
- 兜底方案：`playwright-cli`

## 依赖cli

- `npx`
- `defuddle`
- `playwright-cli`
- `playwright`

## 主方案：`defuddle`

```bash
npx defuddle parse "[url]"
```

## 兜底方案：`playwright-cli`

适合：

- 反爬（微信文章等）

当 `defuddle` 失败、内容不完整、页面难爬时，再用 `playwright-cli`。

设置环境变量 `PLAYWRIGHT_MCP_OUTPUT_DIR=/tmp/.playwright-cli`，否则在当前目录生成snapshot

可以使用这条命令读取特定页面内容：

```bash
# 幂等获取
export PLAYWRIGHT_MCP_OUTPUT_DIR=/tmp/.playwright-cli && playwright-cli open && playwright-cli goto '[url]' && sleep 0.3 && playwright-cli eval "document.body.innerText"

# 当所有url不再爬取
playwright-cli close
```

## 注意事项

- 等待秒数一般不需要很长，除非要加载很久才显示，根据情况调整
- 多个详情也是要改动这条命令，做到开一次，循环多次爬取
- `playwright-cli` 读出来的是整页可见文字，不保证是干净正文
