---
name: create-task
description: 当需要在特定机器（如 mio）或全部机器上创建、修改、测试声明式定时任务（Task）时阅读该技能
---

# 声明式定时任务 SOP

用于指导 Agent 在 macOS 节点上创建、修改与验证轻量级声明式定时任务

## 任务规范

- **机器专属任务**：存放于 `hosts/<host>/tasks/<name>.nix`
- **全设备通用任务**：存放于 `modules/features/darwin/tasks/_global/<name>.nix`，文件为完整 darwin 模块：`{ pkgs, ... }: { shelken.tasks.<name> = { ... }; }`，参考 `_global/nix-gc.nix`
- **零接线约定**：在对应目录下放置 nix 文件即自动注册，无需在 host 主配置中添加任何引用代码

## 字段定义与规则

| 字段       | 类型         | 默认值  | 约束与说明                                                                             |
| ---------- | ------------ | ------- | -------------------------------------------------------------------------------------- |
| `when`     | 字符串或列表 | 无      | 日历时间，如 `"3:15"` 或 `[ "3:15" "15:15" ]`；睡眠唤醒后自动补跑；与 `every` 互斥     |
| `every`    | 整数（秒）   | 无      | 固定间隔执行，如 `7200` 表示每 2 小时；与 `when` 互斥                                  |
| `user`     | 布尔值       | `true`  | `true` 为用户态 LaunchAgent，`false` 为系统 root 态 LaunchDaemon                       |
| `island`   | 布尔值       | `false` | 是否在灵动岛显示任务运行状态                                                           |
| `packages` | package 列表 | `[ ]`   | 脚本依赖的 CLI 工具，自动注入隔离的运行时 PATH，脚本内直接调用命令                     |
| `secrets`  | 属性集       | `{ }`   | 环境变量到 `secretPath "sops/key"` 的映射，运行时按需注入                              |
| `script`   | bash 脚本    | 必填    | 脚本正文，构建期经 `bash -n` 语法检查（shellcheck 只覆盖框架生成的包装脚本，不含正文） |

## 创建流程

### 1. 编写任务文件

在对应主机的 tasks 目录下新建 「<name>.nix」:

```nix
{ pkgs, ... }:
{
  when = "3:15";
  user = true;
  packages = with pkgs; [ jq curl ];
  script = ''
    echo "task triggered"
  '';
}
```

### 2. Flake 暂存与构建

新增文件必须被 git 追踪, 否则 Flake 无法识别:

```bash
git add hosts/<host>/tasks/<name>.nix
just bd
```

### 3. 查看调度表

`task ls` 读的是已部署的 launchd 任务（用户态 `~/Library/LaunchAgents`、root 态 `/Library/LaunchDaemons`），`just bd` 只构建不部署。应用后（用户态任务 `just hm`、root 任务 `just sw`，均需用户授权）检查任务是否正确列出:

```bash
task ls
```

### 4. 手动运行与验证

调用统一管理 CLI 验证执行与排障:

```bash
# 手动运行任务(root 任务自动引导 sudo)
task run <name>

# 实时查看任务日志
task log <name>
```

## 常见排坑指南

- 新建任务在 `task ls` 中未列出：新建文件未执行 `git add`，Flake 处于未追踪状态忽略了该文件
- 脚本内命令报 `command not found`：在任务文件的 `packages` 列表中声明该工具包，避免硬编码 store 绝对路径
- 时间格式解析报错：`when` 必须为 `"H:M"` 格式，不支持标准 cron 表达式
- root 任务清理日志失败：检查日志目录权限，确认 `user = false`，并在手动测试时使用 `sudo task-<name>`
