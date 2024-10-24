{
  myvars,
  lib,
  ...
}: let
  theme = "catppuccin-${lib.strings.toLower myvars.catppuccin_flavor}";
  origin_file = builtins.readFile ./config.kdl;
  inherit (lib) concatStrings;
in {
  programs.zellij = {
    enable = true;
    # settings = {
    #   theme = theme;
    # };
    enableBashIntegration = false;
    enableZshIntegration = false;
  };

  xdg.configFile."zellij/config.kdl" = {
    text = concatStrings [
      ''
        // 主题配色
        theme "${theme}"
      ''
      origin_file
    ];
  };
}
