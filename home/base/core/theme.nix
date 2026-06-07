{
  catppuccin,
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
    # one of "latte", "frappe", "macchiato", "mocha"
    flavor = "macchiato";
    # one of "blue", "flamingo", "green", "lavender", "maroon", "mauve", "peach", "pink", "red", "rosewater", "sapphire", "sky", "teal", "yellow"
    accent = "pink";
  };
}
