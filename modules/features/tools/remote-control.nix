# 远程桌面客户端（Windows App）
{ config, ... }:
{
  flake.modules.darwin.workstation.imports = [ config.flake.modules.darwin.remote-control ];

  flake.modules.darwin.remote-control.homebrew.casks = [ "windows-app" ];
}
