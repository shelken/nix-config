# 快速上手

当前主机由仓库根目录的 `.host-profile`（`PROFILE=<主机>`）决定，首次设置见根目录 [README](../../README.md)「初始化」

## 日常修改与切换

1. 修改 `modules/features/<分类>/<功能>` 或 `hosts/<主机>/`，写法见 [功能与角色](02-features.md)
2. 若新增或删除了文件，先执行 `git add`（flake 不识别未跟踪文件）
3. 运行 `just bd` 验证构建，确认无误后运行 `just sw` 切换系统，或运行 `just hm` 仅切换 Home Manager

完整配方运行 `just --list` 查看；静态资源的 rev 钉在 `flake.nix`（见 [ADR 0006](../adr/0006-static-assets-as-flake-inputs.md)），`just up` 不会推动它们，由 Renovate 开 PR 更新

## 构建前检查编译量

```bash
just plan                  # 当前机器的系统
just plan mio home         # mio 的 Home Manager
just plan vps-cc deploy    # vps-cc 的 deploy-rs 部署 profile
```

发现不希望现编的包时，用 `.drv` 路径追查依赖来源：

```bash
nix why-depends --derivation .#darwinConfigurations.<主机>.system <.drv 路径>
```

## 进一步阅读

- [功能与角色](02-features.md)
- [声明式定时任务](01-tasks.md)
- [备份](04-backup.md)
