{ config, ... }:
{
  flake.modules.darwin.core.imports = [ config.flake.modules.darwin.xdg ];

  flake.modules.homeManager.xdg = {
    xdg.enable = true;
  };
}
