---
name: browser-best-practice
description: 当需要控制浏览器时阅读该技能
---

## 工具选择

- 在 Oh My Pi（omp）环境中，有 `browser` 时默认使用它，不使用 `playwright-cli`
- 使用 `playwright-cli` 前，运行 `playwright-cli --help` 确认基本用法

## 浏览器连接与会话

- 调试时优先通过 CDP 连接用户的主要浏览器，首选 Chrome；结束后关闭自己开启的浏览器进程
- 连接非 Chrome 浏览器时，默认检查 9333 端口；没有监听则停止，让用户以开启监听的方式重新打开浏览器
- 连接入口：`playwright-cli attach --cdp http://127.0.0.1:9333 -s=<名> >/tmp/<名>.log 2>&1 &`；attach 是长驻 daemon，必须后台运行
- 连接成功后，用 `playwright-cli -s=<名> <命令>` 操作；网络观测先用 `goto` 刷新建立基线，再用 `requests` 和 `request/response-body <序号>`

## 截图与产物

- 截图用 `screenshot --filename <路径>`，位置参数是元素选择器；高清验收图先 `resize 1920 1080`，再加 `--full-page --hires`
- 必须使用 `PLAYWRIGHT_MCP_OUTPUT_DIR=/tmp/playwright-cli-{name}` 指定输出目录，否则产物会落在当前目录；结束后自行清理 `.playwright-cli` 目录
