# Nix 全局设置：flakes、substituters、trusted-users 与 store 优化；GC 见 gc.nix
# Darwin 上的 /etc/nix/nix.conf 由 Determinate 接管，见 features/darwin/nix/
{ config, lib, ... }:
{
  flake.modules.nixos.core.imports = [ config.flake.modules.nixos.nix-settings ];

  flake.modules.nixos.nix-settings =
    { myvars, pkgs, ... }:
    {
      nix.package = pkgs.nix;

      # to install chrome, you need to enable unfree packages
      nixpkgs.config.allowUnfree = lib.mkForce true;

      # Manual optimise storage: nix-store --optimise
      # https://nixos.org/manual/nix/stable/command-ref/conf-file.html#conf-auto-optimise-store
      nix.settings.auto-optimise-store = true;

      nix.channel.enable = false; # remove nix-channel related tools & configs, we use flakes instead.

      nix.settings = {
        # enable flakes globally
        experimental-features = [
          "nix-command"
          "flakes"
        ];

        trusted-users = [ myvars.username ];

        # substituers that will be considered before the official ones(https://cache.nixos.org)
        substituters = [

          "https://nix-community.cachix.org"
        ];

        trusted-public-keys = [
          "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        ];
        builders-use-substitutes = true;
      };
    };
}
