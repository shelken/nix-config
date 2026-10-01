---
name: nix-best-practice
description: 当需要 处理 nix/nix-config/home-manager等等和nixos/nix相关内容 时阅读该技能
---

## 包查找与命令约束

- 搜索包时优先使用 `nh search {package-name}`
- 未经用户同意，不执行 `nix run`、`nix shell` 等命令；不使用 `with import <nixpkgs>` 这类写法
