{ config, ... }:
let
  inherit (config.flake.modules) darwin nixos;
in
{
  flake.modules.darwin.gui.imports = [ darwin.tui ];
  flake.modules.nixos.gui.imports = [ nixos.tui ];
}
