---
name: verify-nix-config
description: 验证 nix-config 的 Darwin、NixOS、Home Manager 与外部源配置。修改 Nix 配置、宿主机定义、Home Manager 或 nvfetcher 源后使用。
---

# 验证 nix-config

## Launch

此仓库没有常驻服务。构建命令就是验证入口，构建不会应用配置。

选择与当前改动相同的平台和宿主机。Darwin 与 Home Manager 使用对应宿主机名作为 `PROFILE`。

```bash
PROFILE=<darwin-host> just bd
PROFILE=<home-host> just hmb
just rebuild-debug <nixos-host>
nvfetcher -c nvfetcher.toml -o _sources
```

命令以零退出码结束即完成。`nh` 会显示生成的 store path 或变更摘要。

## Doctor

先确认当前 checkout 可求值，并且目标名称存在。

```bash
nix flake show --no-write-lock-file
```

从输出选择 `darwinConfigurations`、`nixosConfigurations` 或 `homeConfigurations` 中的目标名。目标不存在或命令失败时，先修复配置，不进行构建。

## Drive

按改动选择特性映射中的一个或多个路径。

- Darwin 改动使用 `features/darwin-system.md`
- Home Manager 改动使用 `features/home-manager.md`
- NixOS 改动使用 `features/nixos-system.md`
- `nvfetcher.toml` 改动使用 `features/external-sources.md`

每次构建均由真实维护者操作路径触发。不要使用 `just sw` 或 `just hm` 作为验证，它们会修改当前机器。

## Evidence

保存命令、完整终端输出和退出码。证据目录位于 `$TMPDIR/nix-config-verify-<timestamp>`。

```bash
: "${TMPDIR:?TMPDIR is required}"
run="$TMPDIR/nix-config-verify-$(date +%Y%m%d%H%M%S)"
mkdir -p "$run"
PROFILE=<host> just bd 2>&1 | tee "$run/darwin-build.log"
test "${PIPESTATUS[0]}" -eq 0
```

证明必须覆盖触发命令和最终生成物。`nvfetcher` 验证还必须保留 `_sources/generated.json` 与 `_sources/generated.nix` 的 diff。

## Cleanup

本验证不启动进程，也不应用系统配置。它不创建证据之外的临时状态。保留 `$run` 供审查，确认后由操作者删除。

## Helpers

不提供辅助脚本。`justfile`、`nvfetcher` 和 `nix` 是唯一入口，命令以它们的当前实现为准。
