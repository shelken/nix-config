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
  catppuccin_theme = mylibx.fromYaml "${catppuccin-lazygit}/themes/${theme_path}";
  base_config = mylibx.fromYaml ./config.yml;
in {
  programs.lazygit = {
    enable = true;
    settings =
      base_config
      // {
        # diff with delta
        gui =
          {
            timeFormat = "2006-01-02 15:04";
            shortTimeFormat = "15:04";
          }
          // catppuccin_theme;
        git.paging = {
          colorArg = "always";
          pager = "delta --dark --paging=never";
        };
      };
  };

  home.packages = with pkgs; [
    # difftastic
    delta
    # 查看文件或分支的历史
    tig
  ];
}
