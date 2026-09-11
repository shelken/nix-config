---
name: nix-best-practice
description: 当需要 处理 nix/nix-config/home-manager等等和nixos/nix相关内容 时阅读该技能
---

## Rules

- 如果搜索包时, 优先用`nh search {package-name}`搜索包
- 除非用户同意, 否则永远不准执行 nix run/nix shell 等命令, 永远不准出现类似`with import <nixpkgs>`的写法
