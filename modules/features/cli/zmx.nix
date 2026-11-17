# zmx：终端会话保持
{ config, ... }:
{
  flake.modules.homeManager.core.imports = [ config.flake.modules.homeManager.zmx ];

  flake.modules.homeManager.zmx =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.zmx ];
    };
}
