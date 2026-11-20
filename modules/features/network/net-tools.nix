{ config, ... }:
{
  flake.modules.homeManager.tui.imports = [ config.flake.modules.homeManager.net-tools ];

  flake.modules.homeManager.net-tools =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        q
        nali
      ];
    };
}
