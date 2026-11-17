# protobuf 编译器
# 开发机 → tui
{ config, ... }:
{
  flake.modules.homeManager.tui.imports = [ config.flake.modules.homeManager.protobuf ];

  flake.modules.homeManager.protobuf =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.protobuf ];
    };
}
