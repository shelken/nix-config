{
  myvars,
  lib,
  ...
}: let
  theme = "catppuccin-${lib.strings.toLower myvars.catppuccin_flavor}";
in {
  programs.zellij = {
    enable = true;
    settings = {
      theme = theme;
    };
  };
}
