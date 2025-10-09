{ pkgs, ... }@args:
let
  sources = pkgs.callPackage ../../_sources/generated.nix { };
in
{
  nixpkgs.overlays = import ../../overlays (args // { inherit sources; });
}
