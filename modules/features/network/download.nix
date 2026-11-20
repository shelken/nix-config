{ config, ... }:
{
  flake.modules.darwin.workstation.imports = [ config.flake.modules.darwin.download ];

  flake.modules.darwin.download.homebrew.casks = [ "motrix" ];
}
