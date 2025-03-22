# colmena - Remote Deployment via SSH
{
  lib,
  inputs,
  nixos-modules,
  home-modules ? [],
  myvars,
  system,
  tags,
  ssh-user ? "root",
  genSpecialArgs,
  specialArgs ? (genSpecialArgs system),
  ...
}: let
  inherit (inputs) home-manager;
in
  {name, ...}: {
    deployment = {
      inherit tags;
      targetUser = ssh-user;
      targetHost = name; # hostName or IP address
    };

    imports =
      nixos-modules
      ++ (
        lib.optionals ((lib.lists.length home-modules) > 0)
        [
          home-manager.nixosModules.home-manager
          ({config, ...}: {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;

            home-manager.extraSpecialArgs = specialArgs // {hostname = config.networking.hostName;};
            home-manager.users."${myvars.username}".imports = home-modules;
          })
        ]
      );
  }
