# flake-parts 不给模块设 key，同一模块导入两次不会去重：每个模块只能有一条导入路径
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
