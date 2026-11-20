{ config, ... }:
{
  flake.modules.darwin.workstation.imports = [ config.flake.modules.darwin.thaw ];

  flake.modules.darwin.thaw = {
    homebrew.casks = [ "thaw" ];
  };
}
