{
  description = "My flake configuration";

  nixConfig = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
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

  outputs =
    inputs@{
      self,
      nixpkgs,
      ...
    }:
    let
      inherit (inputs.nixpkgs) lib;
      mylib = import ./lib { inherit lib; };
      myvars = import ./vars { inherit lib; };

      genSpecialArgs =
        system:
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
      args = {
        inherit
          inputs
          lib
          mylib
          myvars
          genSpecialArgs
          ;
      };
      pve155Modules = {
        system = "x86_64-linux";
        nixos-modules = map mylib.relativeToRoot [
          "modules/nixos/server.nix"
          "hosts/pve155"
          # "modules/nixos/hyprland.nix"
        ];
        home-modules = map mylib.relativeToRoot [
          "home/linux/core.nix"
        ];
      }
      // args
      // {
        system = "x86_64-linux";
      };
      pve156Modules = {
        system = "x86_64-linux";
        nixos-modules = map mylib.relativeToRoot [
          "modules/nixos/server.nix"
          "hosts/pve156"
        ];
        home-modules = map mylib.relativeToRoot [
          "home/linux/core.nix"
        ];
      }
      // args
      // {
        system = "x86_64-linux";
      };
      armTest1Modules = {
        nixos-modules = map mylib.relativeToRoot [
          "modules/nixos/desktop.nix"
          "hosts/vm/arm-test-1"
        ];
        home-modules = map mylib.relativeToRoot [
          "home/linux/gui.nix"
          "hosts/vm/arm-test-1/home.nix"
        ];
      }
      // args
      // {
        system = "aarch64-linux";
      };
      workTestModules = {
        nixos-modules = map mylib.relativeToRoot [
          "modules/nixos/server.nix"
        ];
        home-modules = map mylib.relativeToRoot [
          "home/linux/tui.nix"
        ];
      }
      // args
      // {
        system = "x86_64-linux";
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
      }
      // args
      // {
        system = "aarch64-darwin";
      };
      sakamotoModules = {
        darwin-modules = map mylib.relativeToRoot [
          "modules/darwin"
          "hosts/sakamoto"
        ];
        home-modules = map mylib.relativeToRoot [
          "home/darwin"
          "secrets/home.nix"
          "hosts/sakamoto/home.nix"
        ];
      }
      // args
      // {
        system = "aarch64-darwin";
      };
      mioModules = {
        darwin-modules = map mylib.relativeToRoot [
          "modules/darwin"
          "hosts/mio"
        ];
        home-modules = map mylib.relativeToRoot [
          "home/darwin"
          "secrets/home.nix"
          "hosts/mio/home.nix"
        ];
      }
      // args
      // {
        system = "aarch64-darwin";
      };
      nanoModules = {
        darwin-modules = map mylib.relativeToRoot [
          "modules/darwin"
          "hosts/nano"
        ];
        home-modules = map mylib.relativeToRoot [
          "home/darwin"
        ];
      }
      // args
      // {
        system = "x86_64-darwin";
      };
      lingModules = {
        darwin-modules = map mylib.relativeToRoot [
          "modules/darwin"
          "hosts/ling"
        ];
        home-modules = map mylib.relativeToRoot [
          "home/darwin"
          "hosts/ling/home.nix"
        ];
      }
      // args
      // {
        system = "aarch64-darwin";
      };

      allSystemAbove = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];
      forAllSystems = func: (nixpkgs.lib.genAttrs allSystemAbove func);
    in
    {
      # linux x86
      nixosConfigurations = {
        nixos = mylib.nixosSystem pve155Modules;
        pve156 = mylib.nixosSystem pve156Modules;
        arm-test-1 = mylib.nixosSystem armTest1Modules;
        work-test = mylib.nixosSystem workTestModules;
      };

      darwinConfigurations = {
        # mac mini
        yuuko = mylib.macosSystem yuukoModules;
        sakamoto = mylib.macosSystem sakamotoModules;
        # macbook air
        mio = mylib.macosSystem mioModules;
        nano = mylib.macosSystem nanoModules;
        ling = mylib.macosSystem lingModules;
      };

      colmena = {
        meta = (
          let
            system = "x86_64-linux";
          in
          {
            # colmena's default nixpkgs & specialArgs
            nixpkgs = import nixpkgs { inherit system; };
            specialArgs = genSpecialArgs system;
          }
        );
      }
      // {
        pve156 = mylib.colmenaSystem (
          pve156Modules
          // {
            tags = [ "pve156" ];
            ssh-user = myvars.username;
          }
        );
      }
      // {
        arm-test-1 = mylib.colmenaSystem (
          armTest1Modules
          // {
            tags = [ "arm-test-1" ];
            ssh-user = myvars.username;
          }
        );
      };

      checks = forAllSystems (system: {
        #ref: https://devenv.sh/?q=git-hooks.hooks
        pre-commit-check = inputs.git-hooks.lib.${system}.run {
          src = ./.;
          hooks = {
            nixfmt-rfc-style = {
              enable = true;
              settings.width = 100;
            };
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
      });

      # Development Shells
      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              # fix https://discourse.nixos.org/t/non-interactive-bash-errors-from-flake-nix-mkshell/33310
              bashInteractive
              # deploy
              colmena
              # Nix-related
              nixfmt
              deadnix
              statix
              # spell checker
              typos
              # code formatter
              nodePackages.prettier
              nixos-anywhere
              nvfetcher
            ];
            name = "dots";
            shellHook = ''
              ${self.checks.${system}.pre-commit-check.shellHook}
            '';
          };
        }
      );

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt);
    };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    # darwin
    #nixpkgs-darwin.url = "github:nixos/nixpkgs/nixpkgs-24.11-darwin";
    nixpkgs-darwin.url = "github:nixos/nixpkgs/nixpkgs-unstable";
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

    # my dotfiles
    dotfiles = {
      url = "github:shelken/dotfiles.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # secrets
    secrets = {
      url = "git+ssh://git@github.com/shelken/secrets.nix.git?shallow=1";
      flake = false;
    };

    ###########################################################

    # anyrun - a wayland launcher
    anyrun = {
      url = "github:/anyrun-org/anyrun/v25.9.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # https://github.com/catppuccin/nix
    catppuccin = {
      url = "github:catppuccin/nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # disko
    disko = {
      url = "github:nix-community/disko/v1.11.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # git-hooks; gen pre-commit-config
    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    niri.url = "github:sodiboo/niri-flake";

    # generate iso/qcow2/docker/... image from nixos configuration
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    rime-main = {
      # 霧凇拼音
      url = "github:iDvel/rime-ice/main";
      flake = false;
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # vscode-server
    vscode-server = {
      url = "github:nix-community/nixos-vscode-server";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
}
