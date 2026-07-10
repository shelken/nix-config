# Determinate Nix 迁移后丢失 nix-community 信任配置

**日期**: 2026-07-02
**影响**: statix 无法使用已有的 nix-community 缓存，转为本地编译
**发现人**: shelken

## 问题

statix 在 `cache.nixos.org` 没有缓存，但在 `nix-community.cachix.org` 有缓存。Darwin 配置虽然包含 nix-community 的 URL，却没有信任对应公钥，因此 Nix 无法使用该缓存并开始本地编译。

排查时模型误以为 nixpkgs revision 太新、缓存尚未生成，一度尝试回退 `flake.lock`。这条判断没有先验证两个缓存的实际命中情况，方向错误。

## 根因

从官方 Nix 配置迁移到 Determinate Nix 后，Darwin 设置了 `nix.enable = false`，`modules/base/nix.nix` 中原有的 nix-community URL 和公钥不再负责实际 Nix 配置，相关设置改由 `modules/darwin/nix.nix` 生成的 `nix.custom.conf` 接管。

Git 历史显示：

- `2701769` 创建 `nix.custom.conf` 时曾同时写入 URL 和公钥。
- `5eaac3d` 后来删除了 `trusted-public-keys`，只留下缓存 URL。
- `c2d4125` 才通过 `extra-trusted-public-keys` 恢复 nix-community 公钥。

根因不是 nixpkgs 太新，而是配置所有权迁移后，缓存 URL 与信任公钥没有作为一组长期保留。

## 修复

在 `modules/darwin/nix.nix` 中同时配置：

- `https://nix-community.cachix.org`
- `nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=`

确认最终配置包含两者后重新构建，优先下载已有缓存，不再为 statix 本地编译。

## 预防

- 缓存 URL 和信任公钥是一个配置单元，新增、迁移或删除时必须一起检查。
- 更换 Nix 安装器或配置所有者时，逐项迁移原有 substituter、公钥和 trusted user，不能只迁移 URL。
- 发现包开始本地编译时，先验证各缓存是否有目标 store path、当前配置是否信任该缓存；不要先改 `flake.lock`。
- 对已有公共缓存的包，默认目标是打通下载链路，而不是接受本地编译。
