{ config, ... }:
{
  flake.modules.darwin.core.imports = [ config.flake.modules.darwin.overlays ];
  flake.modules.nixos.core.imports = [ config.flake.modules.nixos.overlays ];

  flake.modules.darwin.overlays = args: {
    nixpkgs.overlays = import ../../../overlays args;
  };

  flake.modules.nixos.overlays = args: {
    nixpkgs.overlays = import ../../../overlays args;
  };
}
