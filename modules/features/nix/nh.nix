# nh：nix 命令的辅助 CLI（构建、切换、差异展示）
# 开发机 → tui
{ config, ... }:
{
  flake.modules.homeManager.tui.imports = [ config.flake.modules.homeManager.nh ];

  flake.modules.homeManager.nh =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.nh ];
    };
}
