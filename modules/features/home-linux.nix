# Linux 用户态基础：home 目录
# 只适用 Linux → 进 nixos.core（darwin 侧由 features/darwin/cli 设置 /Users）
{ config, ... }:
{
  flake.modules.nixos.core.imports = [ config.flake.modules.nixos.home-linux ];

  flake.modules.homeManager.home-linux =
    { myvars, ... }:
    {
      home.homeDirectory = "/home/${myvars.username}";
    };
}
