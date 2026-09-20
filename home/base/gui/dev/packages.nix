{
  pkgs,
  ...
}:
{
  programs.television.enable = true; # catppuccin 主题经 autoEnable 注入
  home.packages = with pkgs; [
    android-tools
    scrcpy
  ];

  home.shellAliases = {

  };
}
