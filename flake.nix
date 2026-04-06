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
      secrets,
      ...
    }:
    let
      inherit (inputs.nixpkgs) lib;
      myvars = import ./vars { inherit lib; };
      mylib = import ./lib { inherit lib secrets myvars; };

      genSpecialArgs =
        system:
        let
          pkgs = import (if lib.hasSuffix "darwin" system then inputs.nixpkgs-darwin else inputs.nixpkgs) {
            inherit system;
            config.allowUnfree = true;
          };
        in
        inputs
        // {
          pkgs-unstable = import inputs.nixpkgs-unstable {
            inherit system; # refer the `system` parameter form outer scope recursively
            # To use chrome, we need to allow the installation of non-free software
            config.allowUnfree = true;
          };

          sources = pkgs.callPackage ./_sources/generated.nix { };

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
      mkHost = cfg: cfg // args;
      hosts = {
        pve155 = mkHost {
          type = "nixos";
          system = "x86_64-linux";
          nixos-modules = map mylib.relativeToRoot [
            "modules/nixos/server.nix"
            "hosts/pve155"
            # "modules/nixos/hyprland.nix"
          ];
          home-modules = map mylib.relativeToRoot [
            "home/linux/core.nix"
          ];
        };
        pve156 = mkHost {
          type = "nixos";
          colmena = true;
          system = "x86_64-linux";
          nixos-modules = map mylib.relativeToRoot [
            "modules/nixos/server.nix"
            "hosts/pve156"
          ];
          home-modules = map mylib.relativeToRoot [
            "home/linux/core.nix"
          ];
        };
        arm-test-1 = mkHost {
          type = "nixos";
          colmena = true;
          system = "aarch64-linux";
          nixos-modules = map mylib.relativeToRoot [
            "modules/nixos/desktop.nix"
            "hosts/vm/arm-test-1"
          ];
          home-modules = map mylib.relativeToRoot [
            "home/linux/gui.nix"
            "hosts/vm/arm-test-1/home.nix"
          ];
        };
        work-test = mkHost {
          type = "nixos";
          system = "x86_64-linux";
          nixos-modules = map mylib.relativeToRoot [
            "modules/nixos/server.nix"
          ];
          home-modules = map mylib.relativeToRoot [
            "home/linux/tui.nix"
          ];
        };
        yuuko = mkHost {
          type = "darwin";
          system = "aarch64-darwin";
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
        sakamoto = mkHost {
          type = "darwin";
          system = "aarch64-darwin";
          darwin-modules = map mylib.relativeToRoot [
            "modules/darwin"
            "hosts/sakamoto"
          ];
          home-modules = map mylib.relativeToRoot [
            "home/darwin"
            "secrets/home.nix"
            "hosts/sakamoto/home.nix"
          ];
        };
        mio = mkHost {
          type = "darwin";
          system = "aarch64-darwin";
          darwin-modules = map mylib.relativeToRoot [
            "modules/darwin"
            "hosts/mio"
          ];
          home-modules = map mylib.relativeToRoot [
            "home/darwin"
            "secrets/home.nix"
            "hosts/mio/home.nix"
          ];
        };
        nano = mkHost {
          type = "darwin";
          system = "x86_64-darwin";
          darwin-modules = map mylib.relativeToRoot [
            "modules/darwin"
            "hosts/nano"
          ];
          home-modules = map mylib.relativeToRoot [
            "home/darwin"
          ];
        };
        ling = mkHost {
          type = "darwin";
          system = "aarch64-darwin";
          darwin-modules = map mylib.relativeToRoot [
            "modules/darwin"
            "hosts/ling"
          ];
          home-modules = map mylib.relativeToRoot [
            "home/darwin"
            "hosts/ling/home.nix"
          ];
        };
      };

      darwinHosts = lib.filterAttrs (_: v: v.type == "darwin") hosts;
      nixosHosts = lib.filterAttrs (_: v: v.type == "nixos") hosts;
      homeHosts = lib.filterAttrs (_: v: v ? "home-modules") hosts;

      colmenaHosts = lib.filterAttrs (_: v: v.colmena or false) hosts;

      colmenaDefaultSystem =
        if colmenaHosts == { } then
          "x86_64-linux"
        else
          (builtins.head (map (h: h.system) (lib.attrValues colmenaHosts)));

      allSystemAbove = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];
      forAllSystems = func: (nixpkgs.lib.genAttrs allSystemAbove func);
    in
    {
      nixosConfigurations = lib.mapAttrs (_: v: mylib.nixosSystem v) nixosHosts;
      darwinConfigurations = lib.mapAttrs (_: v: mylib.macosSystem v) darwinHosts;
      homeConfigurations = lib.mapAttrs (name: v: mylib.mkHomeConfig name v) homeHosts;

      colmena = {
        meta = (
          let
            system = colmenaDefaultSystem;
          in
          {
            # colmena's default nixpkgs & specialArgs
            nixpkgs = import nixpkgs { inherit system; };
            specialArgs = genSpecialArgs system;
          }
        );
      }
      // lib.mapAttrs (
        name: v:
        mylib.colmenaSystem (
          v
          // {
            tags = [ name ];
            ssh-user = myvars.username;
          }
        )
      ) colmenaHosts;

      checks = forAllSystems (system: {
        #ref: https://devenv.sh/?q=git-hooks.hooks
        pre-commit-check = inputs.git-hooks.lib.${system}.run {
          src = ./.;
          hooks = {
            #NOTE 目前不支持配置垂直对其
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
              prettier
              nixos-anywhere
              nvfetcher
              # nh # 不要引入，会把nix放进来
              nix-prefetch-github
              nix-prefetch-git
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
    #nixpkgs-darwin.url = "github:nixos/nixpkgs/nixpkgs-25.11-darwin";
    nixpkgs-darwin.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin";
      # inputs.nixpkgs.follows = "nixpkgs";
      inputs.nixpkgs.follows = "nixpkgs-darwin";
    };

    home-manager = {
      #url = "github:nix-community/home-manager/release-25.11";
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
      url = "github:shelken/secrets.nix?shallow=1";
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
