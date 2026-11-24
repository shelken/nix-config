# 会话归档

把长期未打开的 agent 会话按月整体打包、压缩并加密，再删除原文件以回收磁盘。术语见 [GLOSSARY.md](../../../../GLOSSARY.md) 的「会话归档」，选项、启用条件与定时调度见 [default.nix](./default.nix) 和 [_archive/default.nix](./_archive/default.nix)

整月打包让 zstd 利用跨文件重复内容，也不再为每个小文件多占磁盘块，在两个月份实测体积比逐文件压缩小约四分之一到一半。成员清单同样加密，因为目录名含项目路径；归档卷放在根目录直属，既不被再次扫描，也仍在 kopia 备份范围内

## 排除原则

权威排除列表见 [_archive/session_archive.py](./_archive/session_archive.py) 的 `plan`。按深度跳过根目录直属文件而非靠后缀猜测：agent 把状态文件放在根目录、会话数据放在子目录，且 SQLite WAL 模式只在 checkpoint 时更新主库 mtime（如 pi 的 `sessions.db`），活跃库也会显得很旧。仅当子目录出现新活跃状态文件时才需补规则，可通过 `run` 末尾的「后缀统计」发现

## 命令

完整子命令见 `session-archive --help`；手动按定时任务运行用 `ntask run session-archive`（首次启用前先跑 `--dry-run`）

- 还原的文件 mtime 为当前时间，下一个封存月才会再次归档，且原归档卷不变；`restore` 不覆盖已存在文件，同一路径跨多个卷时先还原序号大的卷才能得到最新版本，恢复整月需逐卷还原
- 查看卷内成员列表：`age -d -i <密钥文件> archive-<月份>.idx.age | zstd -d`（输出路径与大小的 JSON 列表）

## 代价

- 归档延迟最长约 `afterDays` 加一个月，当月与上月数据不会归档
- 只能整卷还原，取回单文件也要还原百 MB 量级的整月卷
- 归档后 pi 与 omp 的 `/resume` 和 `history` 搜不到对应会话，需先 `restore`
- 打包校验与删除原文件之间存在极短竞态窗口，严格保证不丢写入需要会话写入方共用互斥锁
- kopia 仍备份这些目录，旧快照里的明文需等保留策略过期才释放空间

## 密钥

复用 sops 的 age 私钥文件，私钥丢失后归档永久不可读，必须在本机以外另有备份

轮换顺序：把新私钥追加到密钥文件 → 运行 `session-archive rekey` 给旧卷补上新公钥 → 删除旧私钥。`age` 无法只改文件头，因此 `rekey` 需要解密再加密每个归档卷，但不重做压缩层，处理数据量为压缩后的体积

## 验证

```bash
python3 modules/features/ai/session-archive/_archive/e2e.py
```

需要 `age` 与 `zstd` 在 `PATH` 中
