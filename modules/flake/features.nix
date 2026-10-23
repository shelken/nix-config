# 同名即同一功能：homeManager.<name> 自动挂到 darwin.<name> / nixos.<name>，
# 系统侧模块被导入（直接或经角色）时，同名的用户态配置随之进入。角色同样适用此规则
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
