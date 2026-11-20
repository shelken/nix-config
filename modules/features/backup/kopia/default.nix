{ config, ... }:
{
  flake.modules.darwin.workstation.imports = [ config.flake.modules.darwin.kopia ];

  flake.modules.homeManager.kopia.imports = [ ./_hm.nix ];
}
