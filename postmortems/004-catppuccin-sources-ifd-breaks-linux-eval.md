# 共享模块读取 catppuccin.sources 导致 Linux 主机无法在 macOS 上求值

**日期**: 2026-10-21
**影响**: PR #117 合并后，pve155、pve156、work-test 在 macOS 上求值失败，`just deploy` 对这些主机会在求值阶段中断
**发现人**: shelken 追问「还有遗漏吗」后由 agent 发现

## 问题

用 Starship 取代 p10k 时，把 `catppuccin.starship` 与 `catppuccin.sources.palette` 放进了所有主机共享的 `home/base/core/`。PR 验证只构建了 mio（darwin），审查也只在 darwin 上渲染。合并后才发现无头 Linux 主机在这台 Mac 上求值失败。

## 现象

```bash
nix eval --raw .#homeConfigurations.pve155.config.home.activationPackage.drvPath
# error: Cannot build '...-catppuccin-install-hook.drv'
```

同一条命令在 #117 之前的提交上正常返回 drv 路径。

## 根因

实际约束：

- catppuccin/nix 的 `sources.*` 是 `buildCatppuccinPort` 产出的 derivation，不是源码路径
- 配置里 `importTOML` 或 `importJSON "${sources.x}/..."` 要在求值期读取 derivation 内的文件，即 IFD
- IFD 的 derivation 属于目标系统（x86_64-linux），在 macOS 上求值必须有 Linux builder，本机没有
- `just deploy` 对 NixOS 主机使用 `nixos-rebuild --target-host`，求值发生在本机

错误假设：

- 「kitty、pi、anyrun 已经在用 `sources.palette`，所以安全」。它们只被带 GUI 的主机导入，其中没有 pve 这类无头 Linux 主机
- 「先修好 `catppuccin.starship` 的写法就够了」。第一次修复改成读 `sources.palette`，仍是同一类 IFD，直到对 pve155 重新求值才暴露

缺失检查点：验证清单没有要求在每种主机类型上求值。

## 修复

`home/base/core/starship.nix` 改为求值期 `builtins.fetchTarball` 取 `catppuccin/palette`，rev 与 hash 读 catppuccin flake 自带的 `pkgs/sources.json`，随 `nix flake update` 同步。生成的 `starship.toml` 与旧产物逐色相同。

arm-test-1 仍失败，原因是桌面模块 `catppuccin-swaylock`，在 #117 之前就存在。

## 预防

- 往 `home/base/core/`、`modules/base/` 等共享模块引入 `catppuccin.<port>` 或 `catppuccin.sources.*` 前，视为 IFD 风险，不要直接用
- 共享模块的改动合并前，在 darwin 主机上对每个 Linux 主机各求值一次

  ```bash
  for h in pve155 pve156 work-test; do
    nix eval --raw ".#homeConfigurations.$h.config.home.activationPackage.drvPath"
  done
  ```

- 对比基线时用上一个已知正常的提交，例如 `nix eval "git+file://$PWD?rev=<rev>#..."`，区分既有问题与新引入的问题
- 需要 catppuccin 色值时，参照 `home/base/core/starship.nix` 的 `fetchTarball` 写法，不读 `catppuccin.sources.*`
