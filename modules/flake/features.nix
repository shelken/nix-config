{ lib, config, ... }:
let
  withHome = lib.mapAttrs (_: hm: {
    home-manager.sharedModules = [ hm ];
  }) config.flake.modules.homeManager;
in
{
  flake.modules.darwin = withHome;
  flake.modules.nixos = withHome;
}
