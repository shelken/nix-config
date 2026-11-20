{ config, ... }:
{
  flake.modules.homeManager.tui.imports = [ config.flake.modules.homeManager.asciinema ];

  flake.modules.homeManager.asciinema =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.asciinema ];
      home.shellAliases.record = "asciinema rec --overwrite -i 1 --rows 28 --cols 140";
    };
}
