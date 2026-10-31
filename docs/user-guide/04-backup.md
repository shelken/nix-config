# 备份

kopia 每天两次把主机上的重要目录快照到自己的 139 WebDAV 仓库，周日同步一次策略。仓库维护由 sakamoto 上常驻的 kopia server 负责，本机不定时维护

`workstation` 角色自带备份（目前只有 mio），前提是主机开了 `shelken.secrets.enable`。实现全在 `modules/features/backup/`

## 它备份什么

| 来源                         | 内容                                                         |
| ---------------------------- | ------------------------------------------------------------ |
| `shelken.backup.backupPaths` | 主机自己列的路径，mio 是 `~/Code`                            |
| `shelken.backup.app.<名字>`  | 各功能模块声明的路径，omp 与 pi 各自声明自己的 sessions 目录 |

`shelken.backup.policy.ignores` 是基础忽略列表，`shelken.backup.ignores` 追加主机自己的模式，两者合并后写到 `<用户>@<主机>` 这个策略目标上。压缩与保留默认如下

| 项   | 默认值                                                                                                             |
| ---- | ------------------------------------------------------------------------------------------------------------------ |
| 压缩 | `zstd-fastest`                                                                                                     |
| 忽略 | `node_modules`、`target`、`.build`、`*.log`、`kaiyuan` 等，见 `modules/features/backup/_kopia/policy-defaults.nix` |
| 保留 | `latest 48`、`daily 30`、`weekly 12`、`monthly 12`                                                                 |

## 加一条要备份的路径

写在主机自己的 `home.nix` 里

```nix
shelken.backup.backupPaths = [
  "${config.home.homeDirectory}/Documents"
];
```

路径必须是绝对路径，否则构建时报错。改完 `git add` 再 `just sw`

功能模块想备份自己的数据，声明 `shelken.backup.app.<模块名>`，不必碰主机配置

## 什么时候跑

| 任务                | 默认时间                                              | 做什么                                 |
| ------------------- | ----------------------------------------------------- | -------------------------------------- |
| `kopia-backup`      | 2:00 到 8:00 之间按 hostname 取两个相隔 12 小时的时刻 | 连仓库，逐路径 `kopia snapshot create` |
| `kopia-policy-sync` | 周日 5:00                                             | 收敛策略                               |

改时间

```nix
shelken.backup.calendarInterval = [ "3:10" "15:10" ];
shelken.backup.policySyncWhen = "5:30";
```

快照任务带 0 到 599 秒的随机抖动，避免多台机器同时压同一个后端；抖动只在 launchd 唤起时生效，手动跑不等待。策略同步任务不带抖动、不上灵动岛

快照任务执行期间会出现在灵动岛。两个任务失败时都会发系统通知，标题分别为 `Kopia Backup`、`Kopia Policy Sync`，点通知打开日志

`kopia-backup` 的抖动窗口最大 10 分钟，也就是说 `when` 到实际开始快照之间可能隔这么久

## 手动跑一次

```bash
task run kopia-backup      # 手动触发一次快照
kopia-backup               # 同上
kopia-backup --dry-run     # 只读预估所有备份来源的文件数与原始大小
task log kopia-backup      # 跟随日志
kopia-policy-sync          # 只收敛策略，让 ignores 改动立刻生效
kopia-maintenance          # 全量维护，只有仓库的维护所有者能执行
```

周日策略同步由 launchd 的 `Weekday = 0` 调度，机器睡眠错过后会在唤醒时补跑。手动执行不受星期限制

kopia 一个仓库只有一个维护所有者。共享的 `main` 仓库由 sakamoto 上的 kopia server 持有，它自己按计划跑快速与全量维护。在其他机器执行 `kopia-maintenance` 会报 `maintenance must be run by designated user`，查看所有者用 `kopia maintenance info`

`kopia-backup --dry-run` 只读扫描所有备份来源，输出当前仓库策略筛选后的文件数和原始大小。实际上传量还会受去重与压缩影响；修改忽略规则后，先运行 `kopia-policy-sync` 再预估

## 改策略

改 `shelken.backup.policy` 或 `shelken.backup.ignores` 之后，可用 `kopia-policy-sync` 手动同步，否则要等周日的定时同步

快照前发现目标策略还不存在时，也会补同步一次，避免新库或新设备的首个快照按默认策略把 `node_modules` 之类传上去

忽略项会先比对再写，压缩与保留策略按配置声明

## 仓库与凭据

| 项       | 值                                                                                |
| -------- | --------------------------------------------------------------------------------- |
| 后端     | WebDAV，`https://drive.<main-domain>/dav/backup/kopia/main`                       |
| 本地缓存 | `~/.cache/kopia/main`，内容与元数据各 1 GiB                                       |
| sops 键  | `kopia/password`、`main-domain`、`drive/webdav/username`、`drive/webdav/password` |

`main-domain` 只存裸域名，URL 与 `/dav/backup/kopia/main` 前缀在 `_kopia/secrets.nix` 的模板里拼。仓库口令与连接配置由 sops 渲染到本机文件，路径见 `_kopia/secrets.nix`

## 看状态与恢复数据

```bash
kopia-ui                   # 本地打开 kopia 界面，已带好口令与仓库配置
```

浏览快照与恢复文件在界面里做。要在命令行直接调 `kopia`，需要先按 `modules/features/backup/_kopia/service.nix` 里 `cliPrelude` 的两行导出 `KOPIA_PASSWORD` 与 `KOPIA_CONFIG_PATH`，这两个变量平时由手动入口和定时任务注入

## 换存储后端

换后端时仓库不通用，S3 建的库不能用 WebDAV 连，需要走 `kopia repository sync-to`

1. 停掉备份任务，避免切换过程中写入
2. `rm -rf ~/.cache/kopia/main` 清掉旧缓存。kopia 的内容缓存按仓库隔离，但格式 blob 缓存只按 900 秒 TTL 判断新旧，旧缓存可能让新仓库按旧格式写入
3. 用 `kopia repository sync-to` 从旧库复制到新库，或直接连新库从头建
4. 改 `modules/features/backup/_kopia/secrets.nix` 的模板与 sops 键，`just sw` 后 `kopia-policy-sync` 收敛一次策略

另外，`hosts/` 下新增或删除目录会改变所有机器的备份时段，因为默认时段按 `hosts/` 里目录名的哈希顺序分配（`mylib.calcUniformSchedule`）

## 实现在哪

```text
modules/features/backup/default.nix            # 挂到 workstation 角色
modules/features/backup/_options.nix           # backupPaths / app / ignores 接口
modules/features/backup/_kopia/default.nix     # calendarInterval / policySyncWhen / policy
modules/features/backup/_kopia/secrets.nix     # sops 键与仓库连接模板
modules/features/backup/_kopia/service.nix     # 两个任务、手动维护、备份与预估入口
modules/features/backup/_kopia/policy-defaults.nix  # 默认策略
```

定时如何生成、日志落在哪、通知与灵动岛的行为见 [声明式定时任务](01-tasks.md)
