{ config, ... }:
{
  flake.modules.darwin.workstation.imports = [ config.flake.modules.darwin.remote-desktop ];
  flake.modules.darwin.gui.imports = [ config.flake.modules.darwin.parsec ];

  flake.modules.darwin.remote-desktop.homebrew.casks = [ "windows-app" ];
  flake.modules.darwin.parsec.homebrew.casks = [ "parsec" ];
}
