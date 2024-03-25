{
  lib,
  inputs,
  darwin-modules,
  home-modules ? [],
  myvars,
  system,
  genSpecialArgs,
  ...
}: let
  inherit (inputs) home-manager nix-darwin nixpkgs;
  specialArgs = genSpecialArgs system;
in
  nix-darwin.lib.darwinSystem {
    inherit system specialArgs;
    modules =
      darwin-modules
      # 保证命令执行与当前flake的input的nixpkgs包一致
      ++ [
        ({lib, ...}: {
          nixpkgs.pkgs = import nixpkgs {inherit system;};
          # make `nix run nixpkgs#nixpkgs` use the same nixpkgs as the one used by this flake.
          nix.registry.nixpkgs.flake = nixpkgs;

          environment.etc."nix/inputs/nixpkgs".source = "${nixpkgs}";
          # make `nix repl '<nixpkgs>'` use the same nixpkgs as the one used by this flake.
          # discard all the default paths, and only use the one from this flake.
          nix.nixPath = lib.mkForce ["/etc/nix/inputs"];
        })
      ]
      ++ (
        lib.optionals ((lib.lists.length home-modules) > 0)
        [
          home-manager.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;

            home-manager.extraSpecialArgs = specialArgs;
            home-manager.users."${myvars.username}".imports = home-modules;
          }
        ]
      );
  }
