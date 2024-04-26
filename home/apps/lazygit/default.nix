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
  base_config = mylibx.fromYaml ./config.yml;
in {
  programs.lazygit = {
    enable = true;
    settings =
      base_config
      // {
        # diff with difftastic
        git.paging.externalDiffCommand = "difft --color=always";
      }
      // catppuccin_theme;
  };

  home.packages = with pkgs; [
    difftastic
    # 查看文件或分支的历史
    tig
  ];
}
