# 构建 Home Manager 配置

维护者修改 `home/`、用户级模块或外部 Skill 映射后，可以构建目标 Home Manager generation 而不修改用户目录。

## Sub-features

- `build`，构建指定 Home Manager generation
- `diff`，查看新旧 generation 的文件和 store path 差异

## How to get to it (user POV)

在 macOS 上进入仓库根目录。运行 `nix flake show --no-write-lock-file` 找到 `homeConfigurations` 目标。以该名字执行 `PROFILE=<host> just hmb`。

## Driving it with just

Preconditions: Nix、nh 和目标架构可用

- 构建，运行 `PROFILE=<host> just hmb`，观察 `home-manager-generation` 构建成功和零退出码
- 查看差异，读取 `nh` 输出并确认变更来自本次配置

## Gotchas

- `just hmb` 只构建，`just hm` 会修改当前用户环境
- 外部 Skill 变更需要先更新 `_sources/`
