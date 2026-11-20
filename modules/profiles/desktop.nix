{ config, ... }:
let
  inherit (config.flake.modules) darwin;
in
{
  flake.modules.darwin.desktop.imports = [ darwin.gui ];
}
