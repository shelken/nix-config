{ config, ... }:
let
  inherit (config.flake.modules) darwin nixos;
in
{
  flake.modules.darwin.tui.imports = [ darwin.core ];
  flake.modules.nixos.tui.imports = [ nixos.core ];
  flake.modules.homeManager.tui = { };
}
