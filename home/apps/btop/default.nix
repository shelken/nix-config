{
  catppuccin-btop,
  myvars,
  lib,
  ...
}: let
  btop_theme = lib.strings.toLower myvars.catppuccin_flavor;
in {
  # https://github.com/catppuccin/btop/blob/main/themes/catppuccin_mocha.theme
  home.file.".config/btop/themes".source = "${catppuccin-btop}/themes";

  # replacement of htop/nmon
  programs.btop = {
    enable = true;
    settings = {
      color_theme = "catppuccin_${btop_theme}";
      theme_background = false; # make btop transparent
    };
  };
}
