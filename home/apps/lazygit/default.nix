{
  pkgs,
  mylibx,
  catppuccin-lazygit,
  lib,
  myvars,
  ...
}: let
  flavor = lib.strings.toLower myvars.catppuccin_flavor;
  accent = "pink";
  theme_path = "${flavor}/${accent}.yml";
  catppuccin_theme = mylibx.fromYaml "${catppuccin-lazygit}/themes-mergable/${theme_path}";
in {
  programs.lazygit = {
    enable = true;
    settings =
      {
        # diff with difftastic
        git.paging.externalDiffCommand = "difft --color=always";
      }
      // catppuccin_theme;
  };

  home.packages = with pkgs; [
    difftastic
  ];
}
