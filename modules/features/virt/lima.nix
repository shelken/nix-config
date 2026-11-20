{ config, ... }:
{
  flake.modules.darwin.desktop.imports = [ config.flake.modules.darwin.lima ];

  flake.modules.darwin.lima.homebrew.brews = [ "lima" ];
}
