{
  lib,
  inputs,
  darwin-modules,
  home-modules ? [ ],
  myvars,
  system,
  genSpecialArgs,
  ...
}:
let
  inherit (inputs) home-manager nix-darwin nixpkgs-darwin;
  specialArgs = genSpecialArgs system;
in
nix-darwin.lib.darwinSystem {
  inherit system specialArgs;
  modules =
    darwin-modules
    ++ [
      (
        { ... }:
        {
          nixpkgs.pkgs = import nixpkgs-darwin {
            inherit system; # refer the `system` parameter form outer scope recursively
            # To use chrome/claude-cli, we need to allow the installation of non-free software
            config.allowUnfree = true;
          };
        }
      )
    ]
    ++ (lib.optionals ((lib.lists.length home-modules) > 0) [
      home-manager.darwinModules.home-manager
      (
        { config, ... }:
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;

          home-manager.extraSpecialArgs = specialArgs // {
            hostname = config.networking.hostName;
          };
          home-manager.users."${myvars.username}".imports = home-modules;
        }
      )
    ]);
}
