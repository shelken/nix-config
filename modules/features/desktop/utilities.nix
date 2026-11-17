# 桌面小工具：stats（菜单栏系统监控）、AppCleaner、The Unarchiver
{ config, ... }:
{
  flake.modules.darwin.gui.imports = [ config.flake.modules.darwin.utilities ];

  flake.modules.darwin.utilities.homebrew.casks = [
    "stats"
    "appcleaner"
    "the-unarchiver"
  ];
}
