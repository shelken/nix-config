{
  inputs,
  lib,
  system,
  specialArgs,
  nixos-modules,
  home-modules ? [],
  myvars,
  ...
}: let
  inherit (inputs) nixpkgs home-manager ;
  # specialArgs = specialArgs;
in
  nixpkgs.lib.nixosSystem {
    inherit system specialArgs;
    modules =
      nixos-modules
      # ++ [
      #   nixos-generators.nixosModules.all-formats
      #   {
      #     # formatConfigs.iso = {config, ...}: {};
      #     formatConfigs.proxmox = {config, ...}: {
      #       # custom proxmox's image name
      #       proxmox.qemuConf.name = "${config.networking.hostName}-nixos-${config.system.nixos.label}";
      #     };
      #   }
      # ]
      ++ (
        lib.optionals ((lib.lists.length home-modules) > 0)
        [
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;

            home-manager.extraSpecialArgs = specialArgs;
            home-manager.users."${myvars.username}".imports = home-modules;
          }
        ]
      );
  }
