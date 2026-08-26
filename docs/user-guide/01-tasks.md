# 声明式定时任务

在 `hosts/<机器>/tasks/` 下加一个 nix 文件，构建切换后即自动生效：定时任务、可执行脚本、手动命令、统一管理 CLI 全部自动生成。

## 快速开始

给 `mio` 加一个带依赖的用户任务，创建 `hosts/mio/tasks/backup-check.nix`：

```nix
{ pkgs, ... }:
{
  when = "3:15"; # 每天 3:15 执行（或 every = 7200 表示每 2 小时）
  user = true; # 用户态任务（默认 true，root 任务设为 false）
  packages = with pkgs; [
    jq
    curl
  ]; # 自动注入 PATH
  script = ''
    echo "check ok"
  '';
}
```

`git add` 后 `just sw`，完成。

## 配置项

| 字段       | 类型           | 默认值 | 说明                                                                  |
| ---------- | -------------- | ------ | --------------------------------------------------------------------- |
| `when`     | `"H:M"` 或列表 | 无     | 日历时间（launchd `StartCalendarInterval`）；睡眠错过的会在唤醒后补跑 |
| `every`    | 整数（秒）     | 无     | 间隔执行（launchd `StartInterval`）；与 `when` 互斥、二选一           |
| `user`     | bool           | `true` | `true`：用户态 LaunchAgent；`false`：root LaunchDaemon                |
| `packages` | package 列表   | `[ ]`  | 依赖的 CLI 工具，注入隔离的运行时 PATH                                |
| `script`   | bash 脚本      | 必填   | 脚本内容，经 shellcheck 校验打包                                      |

## 统一管理命令 (`task`)

系统提供全局 `task` 命令一站式管理所有定时任务：

```bash
# 1. 查看所有已注册任务、调度时间、权限层与日志路径
task ls

# 输出示例：
# NAME TIER SCHEDULE LOG
# ---- ---- -------- ---
# loon root every 7200s /Library/Logs/task-loon.log
# nix-gc root when 3:15 /Library/Logs/task-nix-gc.log

# 2. 手动执行任务（root 任务自动引导 sudo）
task run loon

# 3. 实时追踪查看任务日志
task log loon
```

底层依然提供独立的 `task-<name>` 可执行文件（如 `task-loon`）。

## 日志输出

所有任务的标准输出与标准错误自动持久化：

- **用户任务 (`user = true`)**：`~/Library/Logs/task-<name>.log`
- **系统任务 (`user = false`)**：`/Library/Logs/task-<name>.log`

## 现有任务示例

```bash
hosts/mio/tasks/loon.nix # 机器专属：每 2h 清理 Loon 日志（root）
modules/darwin/tasks/gc.nix # 全设备默认：每天 3:15 nix GC（root）
```

- 机器专属任务：放 `hosts/<host>/tasks/`
- 全设备通用任务：放 `modules/darwin/tasks/`

## 边界

此模型只覆盖"定时跑一段脚本"。需要 secrets、复杂 policy 配置的重型服务（如 kopia 备份）仍走常规 module（`home/darwin/tasks/kopia/`）。
