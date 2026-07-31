---
name: browser-best-practice
description: 当需要控制浏览器时使用
---

## Rules

- 有playwright-cli命令时, 运行`playwright-cli --help`检查基本用法
- 如果在项目内, 有`.gitignore`文件, 确保加上忽略`.playwright-cli`目录,snapshot时会有大量日志和文件产生; 不在项目内, 用完必须移除目录
- 调试时, 尝试连接用户的主要浏览器或者chrome, 优先使用chrome; 通过CDP连接chrome; 运行结束后必须关闭自己开启的浏览器进程
