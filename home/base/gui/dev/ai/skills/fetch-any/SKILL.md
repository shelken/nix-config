---
name: fetch-any
description:
  当任务涉及 `npx defuddle parse`、`playwright-cli`
  这些命令，或要搜索网页内容、抓取具体网页正文时使用。尤其是需要用真实浏览器搜索和获取难以获取的网站
---

具体做法分开放在：

- [references/fetch.md](references/fetch.md)

## 什么情况调用什么

适用情况：

- 用户要找网页、文章、帖子、社媒内容
- 常规搜索工具结果差、缺内容、被拦截
- 目标站点更适合用用户真实浏览器会话搜索

### 需要抓具体网页时

看 [references/fetch.md](references/fetch.md)

适用情况：

- 用户已经给了 URL
- 需要获取某个具体网页正文
- 页面被反爬、需要本地兜底抓取
