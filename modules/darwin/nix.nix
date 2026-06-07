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
  environment.etc."nix/nix.custom.conf".text = ''
    substituters = https://icache.ooooo.space/cache.nixos.org https://cache.nixos.org https://mirrors.ustc.edu.cn/nix-channels/store https://nix-community.cachix.org
    fallback = true
    builders-use-substitutes = true
    trusted-users = shelken nixos
    # builders = ssh-ng://nix-builder aarch64-linux / 4 1 big-parallel,kvm; ssh://shelken@10.211.55.6 aarch64-linux - 4 1 big-parallel
    # extra-platforms = aarch64-linux
  '';

  nix.gc.automatic = false;

  system.stateVersion = 5;
}
