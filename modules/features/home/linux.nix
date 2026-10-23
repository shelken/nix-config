# Linux 用户 home 目录；darwin 侧见 ./darwin.nix
{ config, ... }:
{
  flake.modules.nixos.core.imports = [ config.flake.modules.nixos.home-linux ];

  flake.modules.homeManager.home-linux =
    { myvars, ... }:
    {
      home.homeDirectory = "/home/${myvars.username}";
    };
}
