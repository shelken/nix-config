---
name: compose-deploy
description:
  Use when 需要通过 task compose:deploy:* 或 compose:sync:* 部署/更新 VPS 或 sakamoto，且命令依赖
  flake+direnv 环境或出现'task:command not found'
---

# Compose Deploy (VPS / sakamoto)

## Overview

在 home-ops 仓库里部署或更新 VPS / sakamoto 的 docker
compose，必须在 flake+direnv 提供的环境里执行 task。

## When to Use

- 需要部署/更新 VPS 或 sakamoto 的 compose 服务
- 需要仅同步配置（不重启容器）
- 需要查看 compose 日志/状态
- 看到 `task: command not found`、`direnv: not allowed`

**When NOT to use**

- 操作 k8s/flux/ansible 时
- 不是 compose 相关任务时

## Core Pattern

```bash
# ❌ 忘了 flake+direnv 环境
task compose:deploy:vps

# ✅ 使用 flake+direnv
direnv exec . task compose:deploy:vps
```

## Quick Reference

| 目的                 | 命令                                         |
| -------------------- | -------------------------------------------- |
| 部署 VPS             | `direnv exec . task compose:deploy:vps`      |
| 部署 sakamoto        | `direnv exec . task compose:deploy:sakamoto` |
| 仅同步 VPS 配置      | `direnv exec . task compose:sync:vps`        |
| 仅同步 sakamoto 配置 | `direnv exec . task compose:sync:sakamoto`   |
| VPS 日志             | `direnv exec . task compose:logs:vps`        |
| VPS 状态             | `direnv exec . task compose:status:vps`      |
| sakamoto 日志        | `direnv exec . task compose:logs:sakamoto`   |
| sakamoto 状态        | `direnv exec . task compose:status:sakamoto` |

> 需要强制重建容器时：在 deploy 命令后追加 `-- --force-recreate`

## Implementation

1. 进入仓库根目录：`cd ~/Code/MyRepo/home-ops`
2. 首次使用先 `direnv allow`
3. 按 Quick Reference 执行对应 task

## Common Mistakes

- 不在仓库根目录执行 → 找不到 Taskfile
- 直接跑 `task ...` → `task: command not found`
- 只需要同步却用 deploy → 不必要的重启
