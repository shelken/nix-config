{
  inputs,
  lib,
  system,
  genSpecialArgs,
  nixos-modules,
  home-modules ? [ ],
  myvars,
  ...
}:
let
  inherit (inputs) nixpkgs home-manager nixos-generators;
  specialArgs = genSpecialArgs system;
in
nixpkgs.lib.nixosSystem {
  inherit system specialArgs;
  modules =
    nixos-modules
    ++ [
      nixos-generators.nixosModules.all-formats
    ]
    ++ (lib.optionals ((lib.lists.length home-modules) > 0) [
      home-manager.nixosModules.home-manager
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
