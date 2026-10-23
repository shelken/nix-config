# nix-index 与 shell 集成
# 所有 darwin 主机 → darwin.core
{ config, ... }:
{
  flake.modules.darwin.core.imports = [ config.flake.modules.darwin.nix-index ];

  flake.modules.homeManager.nix-index.imports = [ ./_index.nix ];
}
