{ config, ... }:
{
  flake.modules.darwin.workstation.imports = [ config.flake.modules.darwin.gitlab ];

  flake.modules.homeManager.gitlab =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.glab ];
    };
}
