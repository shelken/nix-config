# Nix 全局设置：flakes、substituters、trusted-users、GC 与 store 优化
# Darwin 上的 /etc/nix/nix.conf 由 Determinate 接管，见 features/darwin/nix.nix
{ config, lib, ... }:
{
  flake.modules.nixos.core.imports = [ config.flake.modules.nixos.nix-settings ];

  flake.modules.nixos.nix-settings =
    { myvars, pkgs, ... }:
    {
      nix.package = pkgs.nix;

      # to install chrome, you need to enable unfree packages
      nixpkgs.config.allowUnfree = lib.mkForce true;

      # do garbage collection weekly to keep disk usage low
      nix.gc = {
        automatic = lib.mkDefault true;
        dates = lib.mkDefault "weekly";
        options = lib.mkDefault "--delete-older-than 7d";
      };

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

        # given the users in this list the right to specify additional substituters via:
        #    1. `nixConfig.substituers` in `flake.nix`
        #    2. command line args `--options substituers http://xxx`
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
