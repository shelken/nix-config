# BetterDisplay: 显示器分辨率与亮度调节
{ config, ... }:
{
  flake.modules.darwin.desktop.imports = [ config.flake.modules.darwin.betterdisplay ];

  flake.modules.darwin.betterdisplay.homebrew.casks = [ "betterdisplay" ];
}
