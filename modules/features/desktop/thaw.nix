# Thaw：菜单栏图标管理
{ config, ... }:
{
  flake.modules.darwin.workstation.imports = [ config.flake.modules.darwin.thaw ];

  flake.modules.darwin.thaw = {
    homebrew.casks = [ "thaw" ];
  };
}
