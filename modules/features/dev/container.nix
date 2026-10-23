# 容器管理（OrbStack）
{ config, ... }:
{
  flake.modules.darwin.desktop.imports = [ config.flake.modules.darwin.container ];

  flake.modules.darwin.container.homebrew.casks = [ "orbstack" ];
}
