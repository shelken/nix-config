# darwin 用户 home 目录；Linux 侧见 ./linux.nix
{ config, ... }:
{
  flake.modules.darwin.core.imports = [ config.flake.modules.darwin.home-darwin ];

  flake.modules.homeManager.home-darwin =
    { myvars, ... }:
    {
      home.homeDirectory = "/Users/${myvars.username}";
    };
}
