{
  description = "My flake configuration";

  nixConfig = {
    experimental-features = ["nix-command" "flakes"];
    #substituters = [
    #  # replace official cache with a mirror located in China
    #  # "https://mirrors.ustc.edu.cn/nix-channels/store"
    #  "https://cache.nixos.org/"
    #];

    # nix communitys cache server
    extra-substituters = [
      "https://nix-community.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };

  outputs = inputs @ {nixpkgs, ...}: let
    inherit (inputs.nixpkgs) lib;
    mylib = import ./lib {inherit lib;};
    myvars = import ./vars {inherit lib;};

    genSpecialArgs = system:
      inputs
      // {
        pkgs-unstable = import inputs.nixpkgs-unstable {
          inherit system; # refer the `system` parameter form outer scope recursively
          # To use chrome, we need to allow the installation of non-free software
          config.allowUnfree = true;
        };
        inherit mylib myvars system;
        inherit (myvars) username userfullname useremail;
      };
    args = {inherit inputs lib mylib myvars genSpecialArgs;};
    pve155Modules = {
      nixos-modules = map mylib.relativeToRoot [
        "hosts/pve155"
        "modules/nixos/hyprland.nix"
      ];
      home-modules = map mylib.relativeToRoot [
        "home/home.nix"
      ];
    };
    pve156Modules = {
      nixos-modules = map mylib.relativeToRoot [
        "hosts/pve156"
      ];
      home-modules = map mylib.relativeToRoot [
        "home/home.nix"
      ];
    };
    yuukoModules = {
      darwin-modules = map mylib.relativeToRoot [
        "modules/darwin"
        "hosts/yuuko"
      ];
      home-modules = map mylib.relativeToRoot [
        "home/darwin"
        "secrets/home.nix"
        "hosts/yuuko/home.nix"
      ];
    };
    nanoModules = {
      darwin-modules = map mylib.relativeToRoot [
        "modules/darwin"
        "hosts/nano"
      ];
      home-modules = map mylib.relativeToRoot [
        "home/darwin"
        "secrets/home.nix"
      ];
    };
    lingModules = {
      darwin-modules = map mylib.relativeToRoot [
        "modules/darwin"
        "hosts/ling"
      ];
      home-modules = map mylib.relativeToRoot [
        "home/darwin"
      ];
    };

    allSystemAbove = [
      "x86_64-linux"
      "aarch64-darwin"
      "x86_64-darwin"
    ];
  in {
    # linux x86
    nixosConfigurations = {
      nixos = mylib.nixosSystem (pve155Modules // args // {system = "x86_64-linux";});
      pve156 = mylib.nixosSystem (pve156Modules // args // {system = "x86_64-linux";});
    };

    darwinConfigurations = {
      # mac mini
      yuuko = mylib.macosSystem (yuukoModules // args // {system = "aarch64-darwin";});
      nano = mylib.macosSystem (nanoModules // args // {system = "x86_64-darwin";});
      ling = mylib.macosSystem (lingModules // args // {system = "aarch64-darwin";});
    };

    # Development Shells
    devShells = nixpkgs.lib.genAttrs allSystemAbove (
      system: let
        pkgs = nixpkgs.legacyPackages.${system};
      in {
        default = pkgs.mkShell {
          packages = with pkgs; [
            # fix https://discourse.nixos.org/t/non-interactive-bash-errors-from-flake-nix-mkshell/33310
            bashInteractive
            # Nix-related
            alejandra
            deadnix
            statix
            # spell checker
            typos
            # code formatter
            nodePackages.prettier
          ];
          name = "dots";
          # shellHook = ''
          #   ${self.checks.${system}.pre-commit-check.shellHook}
          # '';
        };
      }
    );

    formatter =
      nixpkgs.lib.genAttrs allSystemAbove (system: nixpkgs.legacyPackages.${system}.alejandra);
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # darwin
    nixpkgs-darwin.url = "github:nixos/nixpkgs/nixpkgs-23.11-darwin";
    nix-darwin = {
      url = "github:lnl7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs-darwin";
    };

    rime-main = {
      # 霧凇拼音
      url = "github:iDvel/rime-ice/main";
      flake = false;
    };

    rime-config = {
      url = "github:shelken/rime-auto-deploy";
      flake = false;
    };

    # astronvim
    astronvim = {
      url = "github:AstroNvim/AstroNvim/v3.45.3";
      flake = false;
    };

    # my astronvim config
    astronvim-config = {
      url = "github:shelken/astro-nvim-config";
      flake = false;
    };

    # hyprland
    hyprland.url = "github:hyprwm/Hyprland";

    # my dotfiles
    dotfiles.url = "github:shelken/dotfiles.nix";

    # secrets management
    agenix = {
      # lock with git commit at 0.15.0
      url = "github:ryantm/agenix/564595d0ad4be7277e07fa63b5a991b3c645655d";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # secrets
    secrets = {
      url = "git+ssh://git@github.com/shelken/secrets.nix.git?shallow=1";
      flake = false;
    };

    #          ╭──────────────────────────────────────────────────────────╮
    #          │                          theme                           │
    #          ╰──────────────────────────────────────────────────────────╯
    # btop主题
    catppuccin-btop = {
      url = "github:catppuccin/btop";
      flake = false;
    };

    catppuccin-bat = {
      url = "github:catppuccin/bat/b19bea35a85a32294ac4732cad5b0dc6495bed32";
      flake = false;
    };

    catppuccin-yazi = {
      url = "github:catppuccin/yazi";
      flake = false;
    };
  };
}
