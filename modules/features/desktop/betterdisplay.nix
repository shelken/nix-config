{ config, ... }:
{
  flake.modules.darwin.desktop.imports = [ config.flake.modules.darwin.betterdisplay ];

  flake.modules.darwin.betterdisplay.homebrew.casks = [ "betterdisplay" ];
}
