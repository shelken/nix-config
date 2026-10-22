# 同名即同一功能：homeManager.<name> 自动挂到 darwin.<name> / nixos.<name>，
# 主机只需导入系统侧同名模块，即同时获得该功能的用户态配置
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
