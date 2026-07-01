{ ... }:
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
  # 用户级配置~/.config/nix/nix.conf不要配置substituters覆盖
  # 调整这个时先确保这个和lock分离, 先让这个switch,再更新
  environment.etc."nix/nix.custom.conf".text = ''
    substituters = https://icache.ooooo.space/cache.nixos.org https://icache.ooooo.space/nix-community.cachix.org https://cache.nixos.org https://nix-community.cachix.org https://mirrors.ustc.edu.cn/nix-channels/store https://install.determinate.systems
    extra-trusted-public-keys = nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=
    fallback = true
    builders-use-substitutes = true
    trusted-users = shelken nixos
    # builders = ssh-ng://nix-builder aarch64-linux / 4 1 big-parallel,kvm; ssh://shelken@10.211.55.6 aarch64-linux - 4 1 big-parallel
    # extra-platforms = aarch64-linux
  '';

  nix.gc.automatic = false;

  system.stateVersion = 5;
}
