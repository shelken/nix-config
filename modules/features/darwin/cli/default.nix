# cli：gh-dash 配置、gitlab cli、comma、nix-search-tv、timeout 等终端工具
# 原 home/darwin/core.nix 迁入；所有 darwin 主机都需要 → darwin.core
{ config, ... }:
{
  flake.modules.darwin.core.imports = [ config.flake.modules.darwin.cli ];

  flake.modules.homeManager.cli = import ./_hm.nix;
}
