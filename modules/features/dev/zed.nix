# Zed 代码编辑器
{ config, ... }:
{
  flake.modules.darwin.desktop.imports = [ config.flake.modules.darwin.zed ];

  flake.modules.darwin.zed.homebrew.casks = [ "zed" ];
}
