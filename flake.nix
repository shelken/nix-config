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
    # extra-substituters = [
    #   "https://hadolint.cachix.org"
    # ];
    # extra-trusted-public-keys = [
    #   "hadolint.cachix.org-1:CdmLJ7MXh5ojKBPUQGYklkbetIdIcC8tgOTGRUnxBjo="
    # ];
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    ...
  }: let
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
        mylibx = import ./lib/extend.nix {
          pkgs = import inputs.nixpkgs {inherit system;};
          secrets = inputs.secrets;
          inherit lib;
        };
        inherit mylib myvars system;
        inherit (myvars) username userfullname useremail;
      };
    args = {inherit inputs lib mylib myvars genSpecialArgs;};
    pve155Modules = {
      nixos-modules = map mylib.relativeToRoot [
        "hosts/pve155"
        # "modules/nixos/hyprland.nix"
      ];
      home-modules = map mylib.relativeToRoot [
        "home/linux"
      ];
    };
    pve156Modules = {
      nixos-modules = map mylib.relativeToRoot [
        "hosts/pve156"
      ];
      home-modules = map mylib.relativeToRoot [
        "home/linux"
      ];
    };
    workTestModules = {
      nixos-modules = map mylib.relativeToRoot [
        "modules/nixos/base"
        "modules/base.nix"
      ];
      home-modules = map mylib.relativeToRoot [
        "home/linux"
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
    forAllSystems = func: (nixpkgs.lib.genAttrs allSystemAbove func);
  in {
    # linux x86
    nixosConfigurations = {
      nixos = mylib.nixosSystem (pve155Modules // args // {system = "x86_64-linux";});
      pve156 = mylib.nixosSystem (pve156Modules // args // {system = "x86_64-linux";});
      work-test = mylib.nixosSystem (workTestModules // args // {system = "x86_64-linux";});
    };

    darwinConfigurations = {
      # mac mini
      yuuko = mylib.macosSystem (yuukoModules // args // {system = "aarch64-darwin";});
      nano = mylib.macosSystem (nanoModules // args // {system = "x86_64-darwin";});
      ling = mylib.macosSystem (lingModules // args // {system = "aarch64-darwin";});
    };

    colmena =
      {
        meta = (
          let
            system = "x86_64-linux";
          in {
            # colmena's default nixpkgs & specialArgs
            nixpkgs = import nixpkgs {inherit system;};
            specialArgs = genSpecialArgs system;
          }
        );
      }
      // {
        pve156 = mylib.colmenaSystem (pve156Modules
          // args
          // {
            tags = ["pve156"];
            ssh-user = myvars.username;
            system = "x86_64-linux";
          });
      };

    checks = forAllSystems (
      system: {
        pre-commit-check = inputs.git-hooks.lib.${system}.run {
          src = ./.;
          hooks = {
            alejandra.enable = true; # formatter
            typos = {
              enable = true;
              settings = {
                write = true; # Automatically fix typos
                configPath = "./.typos.toml"; # relative to the flake root
              };
            }; # Source code spell checker
            prettier = {
              enable = true;
              settings = {
                write = true; # Automatically format files
                configPath = "./.prettierrc.yaml"; # relative to the flake root
              };
            }; # 主要用于文档检查
            # deadnix.enable = true; # detect unused variable bindings in `*.nix`
            # statix.enable = true; # lints and suggestions for Nix code(auto suggestions)
          };
        };
      }
    );

    # Development Shells
    devShells = forAllSystems (
      system: let
        pkgs = nixpkgs.legacyPackages.${system};
      in {
        default = pkgs.mkShell {
          packages = with pkgs; [
            # fix https://discourse.nixos.org/t/non-interactive-bash-errors-from-flake-nix-mkshell/33310
            bashInteractive
            # deploy
            colmena
            # Nix-related
            alejandra
            deadnix
            statix
            # spell checker
            typos
            # code formatter
            nodePackages.prettier
            # tools
            nix-prefetch-git
            nix-prefetch-github
          ];
          name = "dots";
          shellHook = ''
            ${self.checks.${system}.pre-commit-check.shellHook}
          '';
        };
      }
    );

    formatter =
      forAllSystems (system: nixpkgs.legacyPackages.${system}.alejandra);
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    # darwin
    nixpkgs-darwin.url = "github:nixos/nixpkgs/nixpkgs-24.05-darwin";
    nix-darwin = {
      url = "github:lnl7/nix-darwin";
      # inputs.nixpkgs.follows = "nixpkgs";
      inputs.nixpkgs.follows = "nixpkgs-darwin";
    };

    home-manager = {
      #url = "github:nix-community/home-manager/release-24.05";
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    rime-main = {
      # 霧凇拼音
      url = "github:iDvel/rime-ice/main";
      flake = false;
    };

    # hyprland
    # hyprland = {
    #   url = "github:hyprwm/Hyprland/v0.38.1";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };

    # my dotfiles
    dotfiles = {
      url = "github:shelken/dotfiles.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # secrets management
    agenix = {
      # lock with git commit at 0.15.0
      url = "github:ryantm/agenix/564595d0ad4be7277e07fa63b5a991b3c645655d";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # secrets
    secrets = {
      url = "git+ssh://git@github.com/shelken/secrets.nix.git?shallow=1";
      flake = false;
    };

    # git-hooks; gen pre-commit-config
    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # generate iso/qcow2/docker/... image from nixos configuration
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # vscode-server
    vscode-server = {
      url = "github:nix-community/nixos-vscode-server/fc900c16";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # superfile = {
    #   url = "github:yorukot/superfile";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };

    #          ╭──────────────────────────────────────────────────────────╮
    #          │                          theme                           │
    #          ╰──────────────────────────────────────────────────────────╯
    # btop主题
    catppuccin-btop = {
      url = "github:catppuccin/btop/21b8d595";
      flake = false;
    };

    catppuccin-bat = {
      url = "github:catppuccin/bat/d714cc1d";
      flake = false;
    };

    catppuccin-yazi = {
      url = "github:catppuccin/yazi/9bfdccc2";
      flake = false;
    };

    catppuccin-lazygit = {
      url = "github:catppuccin/lazygit/21a25afd";
      flake = false;
    };
  };
}
