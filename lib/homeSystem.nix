{
  inputs,
  lib,
  system,
  genSpecialArgs,
  home-modules,
  hostname,
  ...
}:
let
  inherit (inputs) home-manager nixpkgs nixpkgs-darwin;
  specialArgs = genSpecialArgs system;
  pkgsSrc = if lib.hasSuffix "darwin" system then nixpkgs-darwin else nixpkgs;
  pkgs = import pkgsSrc {
    inherit system;
    config.allowUnfree = true;
    overlays = import ../overlays specialArgs;
  };
in
home-manager.lib.homeManagerConfiguration {
  inherit pkgs;
  modules = home-modules;
  extraSpecialArgs = specialArgs // {
    hostname = hostname;
  };
}
