# IntelliJ IDEA 的命令行包装（idea <path>）：cask 在 dev/ide.nix，跟它同一角色 workstation
{ config, ... }:
{
  flake.modules.darwin.workstation.imports = [ config.flake.modules.darwin.idea ];

  flake.modules.homeManager.idea = import ./_script.nix;
}
