# 声明式定时任务

在 `hosts/<机器>/tasks/` 下加一个 nix 文件，构建切换后即自动生效：定时任务、可执行脚本、手动命令三样全部自动生成。

## 快速开始

给 `mio` 加一个任务，创建 `hosts/mio/tasks/backup-check.nix`：

```nix
{
  when = "3:15"; # 每天 3:15 执行
  script = ''
    echo "check ok"
  '';
}
```

`git add` 后 `just sw`，完成。

## 配置项

| 字段     | 类型           | 默认值 | 说明                                                                  |
| -------- | -------------- | ------ | --------------------------------------------------------------------- |
| `when`   | `"H:M"` 或列表 | 无     | 日历时间（launchd `StartCalendarInterval`）；睡眠错过的会在唤醒后补跑 |
| `every`  | 整数（秒）     | 无     | 间隔执行（launchd `StartInterval`）；与 `when` 互斥、二选一           |
| `user`   | bool           | `true` | `true`：用户态 home-manager agent；`false`：root launchd daemon       |
| `script` | bash 脚本      | 必填   | 脚本内容，经 shellcheck 校验打包                                      |

## 生成物

以任务名 `loon` 为例：

- 定时任务：`user = true` 时为用户 LaunchAgent（`launchctl list | grep loon`）；`user = false` 时为系统 LaunchDaemon
- 手动命令：`task-loon`（root 任务需 `sudo task-loon`）
- 脚本本体：`writeShellApplication` 打包进 nix store

## 现有任务示例

```bash
# 仓库内两个实例
hosts/mio/tasks/loon.nix     # 机器专属：每 2h 清理 Loon 日志（root）
modules/darwin/tasks/gc.nix  # 全设备默认：每天 3:15 nix GC（root）
```

设备专属任务放 `hosts/<host>/tasks/`；所有设备都要的任务放 `modules/darwin/tasks/`（文件存在即启用）。

## 验证

```bash
# 查看任务是否注册（root 任务）
launchctl print system/org.nixos.<任务名>

# 用户任务注册在 user domain
launchctl print user/$(id -u)/space.ooooo.<任务名>

# 手动跑一次（root 任务；用户任务去掉 sudo）
sudo task-<任务名>

# 立即触发定时器验证效果（root 任务；用户任务把 system 换成 user/$(id -u)）
sudo launchctl kickstart system/org.nixos.<任务名>
```

## 边界

此模型只覆盖"定时跑一段脚本"。需要 secrets、额外 CLI 工具或多层配置的复杂服务（如 kopia 备份）仍走常规 module（`home/darwin/tasks/kopia/`）。
