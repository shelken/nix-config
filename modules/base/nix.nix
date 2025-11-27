{
  myvars,
  pkgs,
  ...
}:
{
  nix.package = pkgs.nix;

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
      #"https://mirrors.ustc.edu.cn/nix-channels/store"
      # "https://nix-cache.ooooo.space"
      "https://mirrors.ustc.edu.cn/nix-channels/store"

      "https://nix-community.cachix.org"
    ];

    trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
    builders-use-substitutes = true;
  };
}
