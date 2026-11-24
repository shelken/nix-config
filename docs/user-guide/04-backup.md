# 备份

`workstation` 角色默认启用 kopia 备份，前提是主机开启 `shelken.secrets.enable`。选项接口见 [backup-options.nix](../../modules/features/backup/backup-options.nix)，策略默认值、定时与仓库模板见 [modules/features/backup/kopia/](../../modules/features/backup/kopia/)，定时任务机制见 [声明式定时任务](01-tasks.md)

## 加备份路径或改时间

在主机的 `home.nix` 中配置后，执行 `git add` 与 `just sw`（路径必须为绝对路径，否则构建报错）：

```nix
shelken.backup = {
  backupPaths = [ "${config.home.homeDirectory}/Documents" ];
  calendarInterval = [ "3:10" "15:10" ];
  policySyncWhen = "5:30";
};
```

功能模块备份自有数据使用 `shelken.backup.app.<模块名>`；改过 `shelken.backup.policy` 或 `shelken.backup.ignores` 后需运行 `kopia-policy-sync` 才会立刻生效

## 手动操作与恢复

```bash
kopia-backup               # 手动快照（等同 ntask run kopia-backup）
kopia-backup --dry-run     # 只读预估文件数与原始大小
kopia-policy-sync          # 立即同步忽略与保留策略
kopia-ui                   # 打开本地 Web 界面浏览与恢复快照
ntask log kopia-backup     # 查看最近一次备份日志
```

仓库维护由维护所有者统一执行，其他机器运行 `kopia-maintenance` 会被拒绝；命令行直调 `kopia` 时需先按 [_service.nix](../../modules/features/backup/kopia/_service.nix) 导出 `KOPIA_PASSWORD` 与 `KOPIA_CONFIG_PATH`

## 换存储后端

不同后端仓库不通用，切换步骤：

1. 停掉备份任务，避免切换期间写入
2. 执行 `rm -rf ~/.cache/kopia/main` 清掉旧缓存（格式 blob 缓存按 900s TTL 复用，不清可能按旧仓库格式写入）
3. 用 `kopia repository sync-to` 迁移旧库，或直接连新库重新初始化
4. 修改 [_secrets.nix](../../modules/features/backup/kopia/_secrets.nix) 的模板与 sops 键，执行 `just sw` 后跑一次 `kopia-policy-sync`
