{ pkgs, ... }@args:
{
  nixpkgs.overlays = import ../../overlays args;
}
