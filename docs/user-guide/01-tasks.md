# 声明式定时任务

声明一处任务，得到四样东西：launchd 定时触发、`task-<名>` 命令、统一管理入口 `task`，以及自动落盘的日志

两个声明位置，效果一致

- `hosts/<机器>/tasks/<名>.nix`，机器专属
- 任意模块里写 `shelken.tasks.<名>`，随功能一起下发

字段名、默认值与脚本包装逻辑都在 `lib/tasks.nix`，本页不复述类型定义

## 加一个机器专属任务

新建 `hosts/mio/tasks/backup-check.nix`

```nix
{ pkgs, ... }:
{
  when = "3:15";
  packages = with pkgs; [
    curl
  ];
  script = ''
    curl --fail --silent https://example.com/health >/dev/null
  '';
}
```

`git add` 这个文件，再跑 `just sw`（新文件没进 git 的话 flake 看不到）。之后用 `task ls` 确认它已注册

文件名去掉 `.nix` 就是任务名，所以上面的任务叫 `backup-check`，日志落在 `~/Library/Logs/task-backup-check.log`

## 在模块里声明任务

功能模块在自己的配置旁边声明任务，`_kopia` 就是这样做的

```nix
shelken.tasks.kopia-backup = {
  when = [ "6:39" "18:39" ];
  jitter = 600;
  island = true;
  packages = [ pkgs.kopia ];
  script = "kopia snapshot create $HOME/Code";
};
```

两个来源合并成同一份任务表，模块声明的任务和主机任务是同一种东西

## 字段

| 字段       | 类型                 | 默认值  | 作用                                                          |
| ---------- | -------------------- | ------- | ------------------------------------------------------------- |
| `when`     | `"H:M"` 或字符串列表 |         | 日历时间，机器睡眠错过的会在唤醒后补跑                        |
| `every`    | 整数，秒             |         | 间隔时间，机器关机期间错过的不会补跑                          |
| `user`     | bool                 | `true`  | `true` 生成用户态 LaunchAgent，`false` 生成 root LaunchDaemon |
| `packages` | package 列表         | `[ ]`   | 脚本依赖的 CLI，注入运行时 PATH                               |
| `secrets`  | 属性集               | `{ }`   | 环境变量到 sops 解密文件路径的映射，运行时读文件注入          |
| `env`      | 属性集               | `{ }`   | 普通环境变量，明文写在这里                                    |
| `jitter`   | 整数，秒或 `null`    | `null`  | 调度唤起后的最大随机延迟，取值 `1` 到 `32767`                 |
| `notify`   | 属性集               | 见下    | `failure = true`、`success = false`、`title = null`           |
| `island`   | bool                 | `false` | 执行期间在灵动岛显示状态                                      |
| `script`   | bash                 | 必填    | 脚本内容，打包时过 shellcheck                                 |

写错字段名或漏写 `script` 会在构建时报错，不会静默按默认值部署

## 触发时间

`when` 和 `every` 必须二选一，同时给或者都不给都会让构建失败

`when` 映射到 launchd 的 `StartCalendarInterval`，`every` 映射到 `StartInterval`。两者的区别只在睡眠与关机期间：`when` 的触发会被补跑，`every` 不会

## 抖动

多台机器打同一个后端时用 `jitter` 错峰

```nix
jitter = 600; # 唤起后随机等 0 到 599 秒
```

手动 `task run` 不等，因为抖动只在 launchd 唤起时生效

## 通知

用户态任务失败时默认弹一条系统通知，点通知打开对应日志。想把成功也报出来，或者换个标题

```nix
notify = {
  success = true;
  title = "Kopia Backup";
};
```

`title` 同时替换成功与失败两种通知的标题。只有 launchd 唤起的运行会发通知，手动 `task run` 保持安静。root 任务不发通知，图形会话不在席时也发不出来

## 灵动岛

`island = true` 让任务执行期间出现在刘海里：执行中转圈，成功自动收回，失败常驻

灵动岛观察者跑在 `gui` 域，只有登录了图形会话才存在。任务本身在 `user` 域照常执行，两者互不影响

## 日志

| 任务类型 | 路径                           |
| -------- | ------------------------------ |
| 用户态   | `~/Library/Logs/task-<名>.log` |
| root     | `/Library/Logs/task-<名>.log`  |

开了灵动岛的任务会再写一份到 `~/Library/Logs/task-island/<名>.log`，供观察者读取。看日志用 `task log <名>`，它跟随真实日志文件

## 命令

```bash
task              # 等同 task ls
task ls           # 列出任务、调度、权限层与日志路径
task run <名>     # 手动执行，root 任务自动引导 sudo
task log <名>     # 跟随该任务的日志
task-<名>         # 绕过 task，直接执行
```

`task` 运行时读已安装的 `space.ooooo.task-*` launchd plist，所以它只显示真正部署到这台机器的任务

## 哪些任务写在哪

| 位置                                     | 用途                   |
| ---------------------------------------- | ---------------------- |
| `hosts/<机器>/tasks/`                    | 机器专属               |
| `modules/features/darwin/tasks/_global/` | 全设备默认的 root 任务 |
| 任意模块的 `shelken.tasks.<名>`          | 功能自带               |

只有 `user = true` 的任务会进用户层。在模块里声明 root 任务会在构建时报错，所以 root 任务要写在 darwin 层的两处目录里

## 实现位置

```text
lib/tasks.nix                                  # 字段契约与脚本包装：mkTaskType、taskDefaults、mkPackage
modules/features/darwin/tasks/_framework.nix   # root 任务转 LaunchDaemon
modules/features/darwin/tasks/_user-tasks.nix  # 用户任务转 LaunchAgent，并安装 task CLI
modules/features/darwin/tasks/_global/         # 全设备默认任务
modules/features/darwin/tasks/_notify.nix      # 通知用的 terminal-notifier
```
