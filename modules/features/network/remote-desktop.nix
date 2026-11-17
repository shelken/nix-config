# 远程桌面客户端（Windows App）
{ config, ... }:
{
  flake.modules.darwin.workstation.imports = [ config.flake.modules.darwin.remote-desktop ];

  flake.modules.darwin.remote-desktop.homebrew.casks = [ "windows-app" ];
}
