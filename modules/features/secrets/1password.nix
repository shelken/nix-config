{ config, ... }:
{
  flake.modules.darwin.workstation.imports = [ config.flake.modules.darwin."1password" ];

  flake.modules.darwin."1password".homebrew.casks = [ "1password" ];
}
