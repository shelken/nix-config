{ config, ... }:
let
  inherit (config.flake.modules) darwin;
in
{
  flake.modules.darwin.workstation.imports = [ darwin.desktop ];
}
