{
  catppuccin,
  myvars,
  pkgs,
  ...
}:
{
  imports = [
    catppuccin.homeModules.catppuccin
  ];

  catppuccin = {
    # The default `enable` value for all available programs.
    enable = true;
    cache.enable = false;
    # issue: https://github.com/catppuccin/nix/issues/927#issuecomment-4456677608
    sources = catppuccin.packages.${pkgs.stdenv.hostPlatform.system}.overrideScope (
      final: prev: {
        whiskers = pkgs.catppuccin-whiskers;
      }
    );
    autoEnable = true;
    inherit (myvars.catppuccin) accent flavor;
  };
}
