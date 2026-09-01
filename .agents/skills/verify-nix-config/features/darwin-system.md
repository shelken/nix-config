# 构建 Darwin 系统

维护者修改 Darwin 模块、Darwin 宿主机定义或共享模块后，可以构建目标 macOS 系统并查看生成的代际差异。

## Sub-features

- `build`，构建指定 Darwin 宿主机
- `diff`，查看新旧系统代际的输出差异

## How to get to it (user POV)

在 macOS 上进入仓库根目录。运行 `nix flake show --no-write-lock-file` 找到目标名。以该名字执行 `PROFILE=<host> just bd`。

## Driving it with just

Preconditions: Nix、nh 和目标架构可用

- 构建，运行 `PROFILE=<host> just bd`，观察 `darwin-system` 构建成功和零退出码
- 查看差异，读取 `nh` 输出中的 `CHANGED`、`ADDED`、`REMOVED`，确认它们对应本次改动

## Gotchas

- `just bd` 只构建，`just sw` 会应用配置
- 未设置 `PROFILE` 时，justfile 无法选择 Darwin 宿主机
- 跨架构目标需要对应构建能力
