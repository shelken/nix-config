# Tinycast 快捷启动与应用唤起
{ config, ... }:
{
  flake.modules.darwin.desktop.imports = [ config.flake.modules.darwin.tinycast ];

  flake.modules.darwin.tinycast.homebrew.casks = [ "shelken/tap/tinycast" ];
}
