# 声明式定时任务

声明一处任务，得到 `task-<名>` 命令、统一管理入口 `task`，以及自动落盘的日志；配置调度后，再由 launchd 自动触发

两个声明位置，效果一致：

- `hosts/<机器>/tasks/<名>.nix`：机器专属
- 任意模块里写 `shelken.tasks.<名>`：随功能一起下发

字段名、默认值与脚本包装逻辑都在 `lib/tasks.nix`，本页不复述类型定义

## 加一个机器专属任务

新建 `hosts/mio/tasks/backup-check.nix`：

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

执行 `git add` 暂存该文件，再运行 `just sw`（新文件未进 git 无法被 flake 识别）；之后使用 `task ls` 确认它已注册

文件名去掉 `.nix` 即为任务名，上面的任务名为 `backup-check`，日志写入 `~/Library/Logs/task-backup-check.log`

## 在模块里声明任务

功能模块可在自身配置旁声明任务，`_kopia` 的实现如下：

```nix
shelken.tasks.kopia-backup = {
  when = [ "6:39" "18:39" ];
  jitter = 600;
  island = true;
  packages = [ pkgs.kopia ];
  script = "kopia snapshot create $HOME/Code";
};
```

两个来源合并为同一份任务表，模块声明的任务与主机专属任务机制完全一致

## 字段

| 字段       | 类型                 | 默认值  | 作用                                                           |
| ---------- | -------------------- | ------- | -------------------------------------------------------------- |
| `enable`   | bool                 | `true`  | 是否部署任务，`false` 时保留声明，不安装 job 与手动命令        |
| `when`     | `"H:M"` 或字符串列表 |         | 日历时间，机器睡眠错过的会在唤醒后补跑                         |
| `weekday`  | 0 到 7 的整数列表    | `[ ]`   | 限制 `when` 的星期，空列表表示每天，0 与 7 均代表周日          |
| `every`    | 整数（秒）           |         | 间隔时间，机器关机期间错过的不会补跑                           |
| `user`     | bool                 | `true`  | `true` 生成用户态 LaunchAgent，`false` 生成 root LaunchDaemon  |
| `packages` | package 列表         | `[ ]`   | 脚本依赖的 CLI 工具，注入隔离的运行时 PATH                     |
| `secrets`  | 属性集               | `{ }`   | 环境变量到 sops 解密文件路径的映射，运行时读文件注入           |
| `env`      | 属性集               | `{ }`   | 普通环境变量，明文写入此处                                     |
| `jitter`   | 整数（秒）或 `null`  | `null`  | 调度唤起后的最大随机延迟，取值 `1` 到 `32767`                  |
| `notify`   | 属性集               | 见下    | 默认 `failure = true`、`success = false`、`title = null`       |
| `island`   | bool                 | `false` | 执行期间在灵动岛显示状态（运行中转圈，成功自动收回，失败常驻） |
| `script`   | bash 脚本            | 必填    | 脚本内容；构建期只做 `bash -n` 语法检查，不跑 shellcheck       |

写错字段名或漏写 `script` 会在构建时直接报错，不会静默按默认值部署

## 触发时间

`when` 和 `every` 互斥，按需二选一：

- `when = "3:15"`：每天的日历时间，对应 launchd 的 `StartCalendarInterval`
- `every = 7200`：间隔秒数，对应 `StartInterval`
- 都不提供：纯手动任务，`task ls` 显示 `manual`，通过 `task run <名>` 执行

`when` 在睡眠期间错过的触发会在唤醒后补跑，多次错过合并为一次补跑；`every` 不补跑，关机期间错过的日历触发亦不补跑

按星期执行时，在 `when` 旁配置 `weekday`，多个星期与多个时间逐一组合：

```nix
when = "5:00";
weekday = [ 0 ]; # 每周日 5:00，睡眠错过后在唤醒时补跑
```

`weekday` 必须配合非空的 `when` 使用，与 `every` 共用会在构建期报错；`task ls` 会显示具体星期（例如 `when Sun 05:00`）

## 临时禁用

在任务声明中配置 `enable = false`，应用配置后 launchd job 与 `task-<名>` 命令会被移除，`task ls` 不再列出该任务

声明依然保留；需要恢复时改回 `enable = true` 重新应用配置即可

## 抖动 (Jitter)

多台机器访问同一后端服务时，使用 `jitter` 错峰：

```nix
jitter = 600; # 唤起后随机等待 0 到 599 秒
```

手动执行 `task run` 不等待，抖动仅在 launchd 唤起时生效

## 通知

用户态任务失败时默认发送一条系统通知，点击通知打开对应日志；若需要成功通知或自定义标题：

```nix
notify = {
  success = true;
  title = "Kopia Backup";
};
```

`title` 同时替换成功与失败两种通知的标题；仅 launchd 唤起的运行会发送通知，手动 `task run` 保持安静；root 任务不发送通知，图形会话不在席时亦不发送

## 灵动岛

`island = true` 让任务执行期间显示在刘海灵动岛中：执行中转圈，成功自动收回，失败常驻

灵动岛观察者运行在 `gui` 域，仅在登录图形会话后生效；任务本身在 `user` 域照常执行，两者互不影响

## 日志

| 任务类型 | 路径                           |
| -------- | ------------------------------ |
| 用户态   | `~/Library/Logs/task-<名>.log` |
| root     | `/Library/Logs/task-<名>.log`  |

启用灵动岛的任务会额外写入一份到 `~/Library/Logs/task-island/<名>.log` 供观察者读取；查看日志使用 `task log <名>`，实时跟随真实日志文件

`task run` 与直接执行 `task-<名>` 在当前终端前台运行，输出只显示在终端，不写入上述日志文件；`task log` 仅展示 launchd 触发后的输出记录

## 命令

```bash
task              # 等同于 task ls
task ls           # 列出任务、调度、权限层与日志路径
task run <名>     # 手动执行任务，root 任务自动引导 sudo
task log <名>     # 追踪并查看该任务的日志
task-<名>         # 绕过 task CLI 直接执行底层脚本
```

`task` 运行时读取已安装的 `space.ooooo.task-*` launchd plist，仅展示真正部署到当前机器的任务

## 任务存放约定

| 位置                                     | 用途                   |
| ---------------------------------------- | ---------------------- |
| `hosts/<机器>/tasks/`                    | 机器专属               |
| `modules/features/darwin/tasks/_global/` | 全设备默认的 root 任务 |
| 任意模块的 `shelken.tasks.<名>`          | 功能自带               |

仅 `user = true` 的任务进入用户层；在模块中声明 root 任务会在构建期报错，root 任务需写在 darwin 层的两处目录中

## 实现位置

```text
lib/tasks.nix                                  # 字段契约与脚本包装：mkTaskType、taskDefaults、mkPackage
modules/features/darwin/tasks/_framework.nix   # root 任务转 LaunchDaemon
modules/features/darwin/tasks/_user-tasks.nix  # 用户任务转 LaunchAgent，并安装 task CLI
modules/features/darwin/tasks/_global/         # 全设备默认任务
modules/features/darwin/tasks/_notify.nix      # 通知组件 terminal-notifier
```
