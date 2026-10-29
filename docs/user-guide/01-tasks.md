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

| 字段       | 类型           | 默认值  | 说明                                                                                                           |
| ---------- | -------------- | ------- | -------------------------------------------------------------------------------------------------------------- |
| `when`     | `"H:M"` 或列表 | 无      | 日历时间（launchd `StartCalendarInterval`）；睡眠错过的会在唤醒后补跑                                          |
| `every`    | 整数（秒）     | 无      | 间隔执行（launchd `StartInterval`）；与 `when` 互斥、二选一                                                    |
| `user`     | bool           | `true`  | `true`：用户态 LaunchAgent；`false`：root LaunchDaemon                                                         |
| `packages` | package 列表   | `[ ]`   | 依赖的 CLI 工具，注入隔离的运行时 PATH                                                                         |
| `secrets`  | 属性集         | `{ }`   | 环境变量到 `secretPath "sops/key"` 的映射，运行时按需注入                                                      |
| `env`      | 属性集         | `{ }`   | 普通环境变量（明文），运行时注入                                                                               |
| `jitter`   | 整数（秒）     | `null`  | launchd 调度触发时的最大随机延迟；手动运行不延迟，`CANCEL_JITTER=true` 跳过                                    |
| `notify`   | 属性集         | 见右    | `failure`（默认 `true`）/`success`（默认 `false`）/`title`（默认 `null`）；仅 launchd 触发且图形会话在席时生效 |
| `island`   | bool           | `false` | 执行时在灵动岛显示状态（失败常驻，成功自动收回）                                                               |
| `script`   | bash 脚本      | 必填    | 脚本内容，经 shellcheck 校验打包                                                                               |

## 统一管理命令 (`task`)

系统提供 `task` 命令，运行时读取当前已安装的 `space.ooooo.task-*` launchd plist：

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
modules/features/darwin/tasks/_global/nix-gc.nix # 全设备默认：每天 3:15 nix GC（root）
```

- 机器专属任务：放 `hosts/<host>/tasks/`
- 全设备通用任务：放 `modules/features/darwin/tasks/_global/`
- 模块自带任务：在 Home Manager 模块里直接写 `shelken.tasks.<name>`（见下）

## 模块声明任务

`hosts/<host>/tasks/` 的目录扫描只是默认来源，`shelken.tasks` 本身就是选项：模块可以直接声明，
与主机任务合并后统一生成 LaunchAgent 与 `task-<name>` 命令。`modules/features/backup/_kopia/`
的定时备份即此形态：

```nix
shelken.tasks.kopia-backup = {
  when = [ "2:30" "14:30" ];
  jitter = 600; # 多机错开，避免同时压同一存储后端
  island = true;
  packages = [ pkgs.kopia ];
  env = { KOPIA_CONFIG_PATH = config.sops.templates."kopia-repository.config".path; };
  secrets = { KOPIA_PASSWORD = config.sops.secrets.kopia-password.path; };
  script = "kopia snapshot create ~/Code";
};
```

只有 `user = true` 的任务会在用户层生成；root 任务由 darwin 层（`hosts/*/tasks/` 或
`modules/features/darwin/tasks/_global/`）声明。

## 边界

此模型覆盖「定时跑一段脚本」再加统一的通知、日志、抖动与灵动岛。功能自身的策略与 CLI 仍写在
自己的模块里，但定时执行一律经 `shelken.tasks` 声明，不再自建 launchd agent——例如
`modules/features/backup/_kopia/`。
