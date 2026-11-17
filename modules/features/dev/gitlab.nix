# GitLab CLI（glab）
# 所有 darwin 主机 → darwin.core
{ config, ... }:
{
  flake.modules.darwin.core.imports = [ config.flake.modules.darwin.gitlab ];

  flake.modules.homeManager.gitlab =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.glab ];
    };
}
