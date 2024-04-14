{
  pkgs,
  catppuccin-yazi,
  catppuccin-bat,
  myvars,
  lib,
  ...
}: let
  bat_flavor = myvars.catppuccin_flavor;
  yazi_theme = lib.strings.toLower myvars.catppuccin_flavor;
in {
  programs.yazi = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    settings = {
      manager = {
        ratio = [2 7 7];
      };
      preview = {
        tab_size = 3;
      };
    };
  };

  home.packages = with pkgs; [
    file
    fd
    exiftool
    mediainfo
  ];

  xdg.configFile = {
    "yazi/theme.toml" = {
      source = catppuccin-yazi + "/themes/${yazi_theme}.toml";
    };
    "yazi/Catppuccin-${yazi_theme}.tmTheme" = {
      source = catppuccin-bat + "/themes/Catppuccin ${bat_flavor}.tmTheme";
    };
  };
}
