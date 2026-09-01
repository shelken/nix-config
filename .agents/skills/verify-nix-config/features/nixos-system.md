# 构建 NixOS 系统

维护者修改 NixOS 模块、Linux 宿主机定义或共享模块后，可以在支持目标架构的环境中构建系统闭包。

## Sub-features

- `build`，构建指定 NixOS 宿主机
- `evaluation`，验证模块与选项求值

## How to get to it (user POV)

在 Linux 或具有对应远程构建能力的环境中进入仓库根目录。运行 `nix flake show --no-write-lock-file` 找到目标名。以该名字执行 `just rebuild-debug <host>`。

## Driving it with just

Preconditions: Nix、nh 和目标架构可用

- 构建，运行 `just rebuild-debug <host>`，观察 `system.build.toplevel` 构建成功和零退出码
- 求值失败，保留完整堆栈，修复模块定义后重试

## Gotchas

- `just rebuild-debug` 是构建入口，`just switch` 会应用配置
- 当前 macOS 环境不能证明 Linux 闭包可构建
