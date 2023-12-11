{
  description = "my flake configuration";

  nixConfig = {
    experimental-features = ["nix-command" "flakes"];
    substituters = [
      # replace official cache with a mirror located in China
      "https://mirrors.ustc.edu.cn/nix-channels/store"
      "https://cache.nixos.org/"
    ];

    # nix communitys cache server
    extra-substituters = [
      "https://nix-community.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # btop主题
    catppuccin-btop = {
      url = "github:catppuccin/btop";
      flake = false;
    };

    # astronvim
    astronvim = {
      url = "github:AstroNvim/AstroNvim/v3.36.0";
      flake = false;
    };

    # my astronvim config
    astronvim-config = {
      url = "github:shelken/astro-nvim-config";
      flake = false;
    };

    # hyprland
    hyprland.url = "github:hyprwm/Hyprland";
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    home-manager,
    ...
  }: let
    system = "x86_64-linux";
    username = "shelken";
    userfullname = "Shelken Pan";
    useremail = "shelken.pxk@gmail.com";
    specialArgs =
      {
        inherit username userfullname useremail;
      }
      // inputs;
  in {
    nixosConfigurations = {
      nixos = nixpkgs.lib.nixosSystem {
        inherit system;
        inherit specialArgs;
        modules = [
          ./hosts/pve155
          ./modules/nixos/hyprland.nix
          home-manager.nixosModules.home-manager
          {
            home-manager = {
              useUserPackages = true;
              useGlobalPkgs = true;
              extraSpecialArgs = specialArgs;
              users.${username} = ./home-manager/home.nix;
            };
          }
        ];
      };
      pve156 = nixpkgs.lib.nixosSystem {
        inherit system;
        inherit specialArgs;
        modules = [
          ./hosts/pve156
          home-manager.nixosModules.home-manager
          {
            home-manager = {
              useUserPackages = true;
              useGlobalPkgs = true;
              extraSpecialArgs = specialArgs;
              users.${username} = ./home-manager/home.nix;
            };
          }
        ];
      };
    };
    formatter.${system} = nixpkgs.legacyPackages.${system}.alejandra;
  };
}
