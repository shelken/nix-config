---
name: browser-best-practice
description: 当需要控制浏览器时阅读该技能
---

## Rules

- 当你在`OH My Pi` (omp) 环境中, 如果有`browser`, 则默认直接使用omp的`browser`, 不使用`playwright-cli`
- 有playwright-cli命令时, 运行`playwright-cli --help`检查基本用法
- 必须使用`PLAYWRIGHT_MCP_OUTPUT_DIR=/tmp/playwright-cli-{name}`指定输出目录, 否则会在当前目录输出, 结束后自行清理`.playwright-cli`目录
- 调试时, 尝试连接用户的主要浏览器或者chrome, 优先使用chrome; 通过CDP连接chrome; 运行结束后必须关闭自己开启的浏览器进程
- 截图: `screenshot --filename <路径>` (位置参数是元素选择器); 高清验收图: `resize 1920 1080` 后加 `--full-page --hires`

### CDP 连接浏览器

- 假如用户需要连接非chrome浏览器,默认情况下,检查9333端口,如果没有监听,停下来,让用户重新以开启监听的方式打开浏览器
- 入口:`playwright-cli attach --cdp http://127.0.0.1:9333 -s=<名> >/tmp/<名>.log 2>&1 &`(attach 是长驻 daemon,必须后台运行),成功后用 `playwright-cli -s=<名> <命令>` 操作;网络观测用 `requests`(先 `goto` 刷新建基线)+ `request/response-body <序号>`
