# IntelliJ IDEA 的命令行包装（idea <path>）：脚本所有 darwin 主机都有，
# 应用 cask 在 dev/ide.nix，只给 workstation
{ config, ... }:
{
  flake.modules.darwin.core.imports = [ config.flake.modules.darwin.idea ];

  flake.modules.homeManager.idea = import ./_script.nix;
}
