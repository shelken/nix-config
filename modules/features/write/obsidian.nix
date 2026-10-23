# Obsidian 知识管理
{ config, ... }:
{
  flake.modules.darwin.workstation.imports = [ config.flake.modules.darwin.obsidian ];

  flake.modules.darwin.obsidian.homebrew.casks = [ "obsidian" ];
}
