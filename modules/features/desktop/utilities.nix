{ config, ... }:
{
  flake.modules.darwin.gui.imports = [ config.flake.modules.darwin.utilities ];

  flake.modules.darwin.utilities.homebrew.casks = [
    "stats"
    "appcleaner"
    "the-unarchiver"
  ];
}
