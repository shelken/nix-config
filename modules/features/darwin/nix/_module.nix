{
  lib,
  nixpkgs-darwin,
  ...
}:
{
  ###################################################################################
  #
  #  Core configuration for nix-darwin
  #
  #  All the configuration options are documented here:
  #    https://daiderd.com/nix-darwin/manual/index.html#sec-options
  #
  # History Issues:
  #  1. Fixed by replace the determinate nix-installer by the official one:
  #     https://github.com/LnL7/nix-darwin/issues/149#issuecomment-1741720259
  #
  ###################################################################################

  #
  # nixpkgs.config.allowBroken = true;

  nix.enable = false;

  # 变更原因：Darwin 使用 Determinate Nix，nix-darwin 不应接管 /etc/nix/nix.conf。
  # 注意：Determinate 主 nix.conf 在 !include 之后又设了 extra-substituters，
  # 会覆盖此处的 extra-substituters（nix #9487）。所以 substituters 必须用
  # 覆盖语义写全完整列表（主文件不设基础 substituters，覆盖不破坏默认）；
  # trusted-public-keys 主文件用 extra- 追加，这里也用 extra- 追加即可。
  # 用户级只有 icache 开关会覆盖 substituters，见 features/nix/icache.nix
  # 调整这个时先确保这个和lock分离, 先让这个switch,再更新
  # 包突然开始本地编译时，先确认缓存里有目标路径（`nix path-info --store <缓存> <路径>`）、
  # 当前配置信任该缓存，不要先回退 flake.lock。改完用 `nix config show substituters`、
  # `nix config show trusted-public-keys` 看最终合并值，不要只看生成的文件
  environment.etc."nix/nix.custom.conf".text = ''
    substituters = https://cache.nixos.org https://nix-community.cachix.org https://install.determinate.systems
    extra-trusted-public-keys = nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=
    fallback = true
    # 整数秒，覆盖 DNS+TCP+TLS；遇丢包黑洞源的最坏等待上限 ≈ attempts × connect-timeout
    connect-timeout = 2
    # 总尝试次数（1 = 不重试）。遇死源直接跳过并 fallback 到后续可用源
    filetransfer-retry-attempts = 1
    builders-use-substitutes = true
    trusted-users = shelken nixos
    # Linux 构建由 Determinate 的 Native Linux Builder 提供，这里不配 builders / extra-platforms：
    # external-builders 由 determinate-nixd 写入 /etc/nix/nix.conf，手写会绕过开通检查。
    # 不生效时看 `determinate-nixd version` 是否列出 native-linux-builder，没有就重新 `determinate-nixd auth login`
    # 例外：主机导入 features/darwin/linux-builder 后，会在本文件末尾追加 builders，改走本机官方 builder
  '';

  # `nix.enable = false`（Determinate）时 nix-darwin 不接管 registry，
  # 直接写 /etc/nix/registry.json，让 `nix run nixpkgs#...` 解析到本 flake
  # 锁定的 nixpkgs-darwin（源已在 store，不重新拉取全局 registry 和另一份 nixpkgs）。
  environment.etc."nix/registry.json".text = builtins.toJSON {
    version = 2;
    flakes = [
      {
        from = {
          type = "indirect";
          id = "nixpkgs";
        };
        to = {
          type = "path";
          path = toString nixpkgs-darwin;
        }
        // lib.filterAttrs (
          n: _: n == "lastModified" || n == "rev" || n == "revCount" || n == "narHash"
        ) nixpkgs-darwin;
        exact = true;
      }
    ];
  };

  system.stateVersion = 5;
}
