---
name: browser-best-practice
description: 当需要控制浏览器时阅读该技能
---

## Rules

- 有playwright-cli命令时, 运行`playwright-cli --help`检查基本用法
- 如果在项目内, 有`.gitignore`文件, 确保加上忽略`.playwright-cli`目录,snapshot时会有大量日志和文件产生; 不在项目内, 用完必须移除目录
- 调试时, 尝试连接用户的主要浏览器或者chrome, 优先使用chrome; 通过CDP连接chrome; 运行结束后必须关闭自己开启的浏览器进程

### CDP 连接浏览器

- 假如用户需要连接非chrome浏览器,默认情况下,检查9333端口,如果没有监听,停下来,让用户重新以开启监听的方式打开浏览器
- 入口：`playwright-cli attach --cdp http://127.0.0.1:9333 --session <名>`，成功后用 `playwright-cli -s=<名> <命令>` 操作；网络观测用 `requests`（先 `goto` 刷新建基线）+ `request/response-body <序号>`
