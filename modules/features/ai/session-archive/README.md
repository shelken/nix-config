# 会话归档

压缩并加密长期没有打开的 agent 会话文件，再删除原文件以回收磁盘。术语见根目录 `GLOSSARY.md` 的「会话归档」

## 工作方式

- 范围：`shelken.sessionArchive.app.<名>` 声明的目录。pi 与 omp 在各自的功能里声明自己的 sessions 目录，其他 agent 照样加一行
- 冷文件：目录下 mtime 超过 `afterDays`（默认 30）天的普通文件，jsonl 与 artifacts 一视同仁
- 归档：`zstd -19` 压缩，`age` 加密成 `<名>.zst.age`，放在原文件旁边
- 启用：加入 `workstation` 角色即生效，没有 enable 开关。主机没开 `shelken.secrets.enable` 时构建报错
- 调度：任务 `session-archive` 每天 4:20 运行。没有任何 app 声明目录时不安装任务。失败只写任务日志，不发通知

## 排除规则

以下文件不归档，权威实现是 `_archive/session-archive.sh` 的 `cold_files`

- 根目录直属的文件
- 子目录里的 `.DS_Store`、`*.zst.age`、`*.part`、`*.lock*`

目录不存在时直接跳过，不报错

agent 把自己的状态文件放在根目录，会话数据放在子目录，所以按深度排除，不靠猜后缀。例如 pi 的 `sessions.db`：SQLite 的 WAL 模式只在 checkpoint 时更新主库的 mtime，正在使用的库也会显得很旧

只有子目录里出现新的活跃状态文件时，才需要补排除规则。`run` 与 `--dry-run` 末尾的「后缀统计」用来发现新类型。误归档的文件可以 `restore`

## 命令

```bash
session-archive run --dry-run     # 只列冷文件数量与原始大小，不写不删
session-archive run               # 归档
session-archive restore <路径>    # 文件或目录（递归）。解回原名，mtime 设为现在，删除 .zst.age
session-archive rekey [路径]      # 用密钥文件里的当前全部公钥重新加密，缺省为全部目录
task run session-archive          # 以任务方式手动跑一次
```

首次启用前先跑 `--dry-run`

## 安全保证

- 校验：先写 `.part` 临时文件，解密解压后与原文件逐字节比对。一致才改名并删除原文件
- 失败时保留原文件并以非零退出码结束。包括比对失败（压缩期间原文件被改动也算）和改名失败
- 单个文件不可读时只记一次失败，继续处理其余文件
- 目录枚举出错（如子目录无权限）只写日志，这次跳过该目录
- 被信号终止时清掉当前 `.part`。`restore` 的 `.part` 是明文，不会留在原目录
- `restore` 不覆盖已存在的文件

## 代价

- 归档后 pi 与 omp 的 `/resume` 和 `history` 搜不到这些会话，需要先 `restore`
- kopia 仍备份这些目录。旧快照里的明文要等保留策略过期才释放空间

## 密钥

复用 sops 的 age 私钥文件，路径由 `shelken.sessionArchive.keyFile` 指定，默认取 `config.sops.age.keyFile`。加密时用文件里的全部公钥，解密时任一把私钥即可。私钥丢失后归档永久不可读，需要在本机以外另有备份

轮换步骤

1. 把新私钥追加到密钥文件
2. 新归档同时对新旧公钥加密
3. 运行 `session-archive rekey`，给旧归档补上新公钥
4. 删除旧私钥

age 无法只改文件头，所以 `rekey` 要解密再加密每个文件。压缩层不重做，处理的数据量是压缩后的大小

## 验证

```bash
bash modules/features/ai/session-archive/_archive/e2e.sh
```

脚本在临时目录里用临时密钥和改过 mtime 的假会话，覆盖 dry-run、归档、排除规则、restore、校验失败、改名失败、不可读文件、中断清理和 rekey。需要 `age` 与 `zstd` 在 PATH
