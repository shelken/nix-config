# Determinate 登录后 Native Linux Builder 未启用，被误判为仓库问题

**日期**: 2026-10-21
**影响**: 在 macOS 上求值 Linux 主机失败；排查中提交了错误的 workaround 和尸检，事后撤销
**发现人**: shelken

## 问题

#117 把 `catppuccin.starship` 放进所有主机共享的配置后，pve155 等 Linux 主机在 Mac 上求值失败。真正原因是 `determinate-nixd` 没有为这台机器启用 Native Linux Builder，仓库本身没有问题。排查时先把它当成仓库缺陷，改了调色板来源，又据此写了错误的尸检。

## 现象

```bash
nix eval --raw ".#homeConfigurations.pve155.config.home.activationPackage.drvPath"
# error: Cannot build '...-catppuccin-install-hook.drv'.
#        Reason: platform mismatch
#        Required system: 'x86_64-linux'
#        Current system: 'aarch64-darwin'
```

aarch64-linux 则报 `executing '.../bash': Undefined error: 0`。

## 根因

实际约束：

- `catppuccin.starship` 与 `catppuccin.sources.*` 在求值期读取 derivation 内的文件（IFD），会触发 Linux 构建
- `Logged in: true` 不等于 builder 已开通。启用时 `determinate-nixd version` 的特性列表含 `native-linux-builder`，`/etc/nix/nix.conf` 含 `external-builders`；这台机器两者都没有
- 用旧 token 刷新登录、重启守护进程都不会重新拉取开通状态，重新 `determinate-nixd auth login` 之后才生效

错误假设：

- 「本机没有 Linux builder」没有验证就写进提交、尸检和 wiki，后来被用户纠正，又在没有证据时撤销
- 把 `system-features` 里的 `apple-virt` 当作 builder 已开启的证据，它是 macOS 的默认值
- 用 `nix build nixpkgs#legacyPackages.aarch64-linux.ponysay` 判断 builder，它只会从缓存下载，`ultimate = False` 且带 `cache.nixos.org` 签名
- 只看到 justfile 里的 `nixos-rebuild --target-host`，漏看 `[linux]` 标记，推断 `just deploy` 在 Mac 上受影响，实际那条配方只在 Linux 上运行
- 在受限的 agent shell 里复现失败，就直接当作仓库问题处理

缺失检查点：没有先看 `determinate-nixd version` 的特性列表。

## 修复

```bash
determinate-nixd auth logout
determinate-nixd auth login        # 粘贴 token 时可复用 /nix/var/determinate/token
determinate-nixd version           # 特性列表出现 native-linux-builder
```

仓库侧无需改动，`catppuccin.starship` 保持原样。同时清理了 `~/.config/nix/nix.conf` 里过期的 `extra-platforms = aarch64-linux`，并在 `modules/darwin/nix.nix` 里写明 Linux 构建由 Determinate 提供。

## 预防

- Mac 上 Linux 求值或构建失败时，先执行 `determinate-nixd version`，确认特性列表含 `native-linux-builder` 且 `/etc/nix/nix.conf` 含 `external-builders`；没有就重新 `auth login`，不要改仓库
- 验证 builder 用必须真实构建的 derivation，并检查产物里的 `uname -m`，不要用缓存里已有的包

  ```bash
  nix build --no-link --print-out-paths --impure --expr \
    '(builtins.getFlake "nixpkgs").legacyPackages.x86_64-linux.runCommand "probe-${toString builtins.currentTime}" {} "echo hi > $out; uname -m >> $out"'
  ```

- 不凭 `system-features` 判断 builder 是否可用
- 对 justfile 配方下结论前，读完整的配方和平台标记 `[linux]` / `[macos]`
- 在 agent 工具 shell 里得到的失败，先在用户终端复现一次，再决定是否改仓库
