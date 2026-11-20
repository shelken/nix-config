{ config, ... }:
{
  flake.modules.darwin.workstation.imports = [ config.flake.modules.darwin.telegram ];

  flake.modules.darwin.telegram.homebrew.casks = [ "telegram" ];
}
