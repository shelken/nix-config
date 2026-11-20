{ config, ... }:
{
  flake.modules.homeManager.tui.imports = [ config.flake.modules.homeManager.nh ];

  flake.modules.homeManager.nh =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.nh ];
    };
}
