# 会话归档

把长期没动过的 agent 会话文件压缩并加密，再删掉原文件，回收磁盘。术语见根目录 `GLOSSARY.md` 的「会话归档」

## 它做什么

- 冷文件：`shelken.sessionArchive.app.<名>` 声明的目录下，mtime 超过 `afterDays`（默认 30）天的普通文件，不区分 jsonl 与 artifacts
- 归档：`zstd -19` 压缩，`age` 加密成 `<名>.zst.age`，原地存放
- 跳过：根目录直属的文件，以及子目录里的 `.DS_Store`、`*.zst.age`、`*.part`、`*.lock*`；目录不存在时静默跳过
- 根目录直属文件是 agent 自己的状态，会话数据都在子目录里，所以按深度排除，不靠猜后缀。例如 pi 的 `sessions.db`：SQLite 在 WAL 模式下主库 mtime 只在 checkpoint 时更新，活跃的库也会显得很旧
- 子目录里出现新的活跃状态文件时才需要补排除规则。`run` 与 `--dry-run` 末尾的「后缀统计」用来发现新类型；误归档可以 `restore`
- 加入 `workstation` 角色即生效，没有 enable 开关；主机没开 `shelken.secrets.enable` 时构建报错
- 每天 4:20 由 `shelken.tasks.session-archive` 运行；失败只写任务日志，不发通知

pi 与 omp 在各自功能里声明自己的 sessions 目录，其他 agent 同样写一行 `shelken.sessionArchive.app.<名>`

## 命令

```bash
session-archive run --dry-run     # 只列冷文件数量与原始大小，不写不删
session-archive run               # 归档
session-archive restore <路径>    # 文件或目录（递归）；解回原名，mtime 为现在，删除 .zst.age
session-archive rekey [路径]      # 用密钥文件里的当前全部公钥重加密，缺省为全部目录
task run session-archive          # 以任务方式手动跑一次
```

首次启用前先跑 `--dry-run`

## 安全

- 先写 `.part` 临时文件，解密解压后与原文件逐字节比对，一致才改名并删原文件；不一致保留原文件，退出码非零
- 压缩期间原文件被改动，比对同样失败
- 改名失败同样保留原文件；单个文件不可读只计入失败，不中断其余文件
- 被信号终止时清掉当前 `.part`，`restore` 的 `.part` 是明文，不会留在原目录
- 目录枚举失败（如子目录无权限）只在日志里报错，该目录这次不被扫描，不影响其他文件
- `restore` 不覆盖已存在的文件
- 归档后 pi 与 omp 的 `/resume`、`history` 搜不到这些会话，需要时先 `restore`
- kopia 仍备份这些目录，旧快照里的明文要等保留策略过期才释放

## 密钥

复用 sops 的 age 私钥文件（`shelken.sessionArchive.keyFile`，默认 `config.sops.age.keyFile`）。加密给文件里的全部公钥，用其中任一把私钥都能解密。私钥丢失，归档永久不可读，需在本机以外另有备份

轮换：

1. 把新私钥追加到密钥文件
2. 新归档同时对新旧公钥加密
3. 运行 `session-archive rekey`，旧归档补上新公钥，压缩层不重做
4. 删除旧私钥

age 没有只改文件头的办法，rekey 要解密再加密每个文件，但只处理压缩后的数据

## 验证

```bash
bash modules/features/ai/session-archive/_archive/e2e.sh
```

在临时目录里用临时密钥与改过 mtime 的假会话，覆盖 dry-run、归档、跳过规则、restore、校验失败、rekey。需要 `age` 与 `zstd` 在 PATH
