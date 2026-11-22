{
  description = "My flake configuration";

  nixConfig.experimental-features = [
    "nix-command"
    "flakes"
  ];

  outputs =
    inputs@{ self, ... }:
    let
      inherit (inputs.nixpkgs) lib;
      myvars = import ./vars { inherit lib; };
      mylib = import ./lib {
        inherit lib myvars;
        inherit (inputs) secrets;
      };

      specialArgs = {
        inherit
          inputs
          self
          mylib
          myvars
          ;
      };
      args = {
        inherit
          inputs
          lib
          mylib
          myvars
          specialArgs
          ;
      };
      hosts = import ./hosts;

      darwinHosts = lib.filterAttrs (_: v: v.type == "darwin") hosts;
      nixosHosts = lib.filterAttrs (_: v: v.type == "nixos") hosts;
    in
    inputs.flake-parts.lib.mkFlake
      {
        inherit inputs;
        specialArgs = { inherit mylib myvars hosts; };
      }
      {
        imports = [
          inputs.flake-parts.flakeModules.modules
          (inputs.import-tree [
            ./modules/flake
            ./modules/features
            ./modules/profiles
          ])
        ];

        systems = [
          "x86_64-linux"
          "aarch64-linux"
          "aarch64-darwin"
        ];

        flake = {
          nixosConfigurations = lib.mapAttrs (_: v: mylib.nixosSystem (v // args)) nixosHosts;
          darwinConfigurations = lib.mapAttrs (_: v: mylib.macosSystem (v // args)) darwinHosts;
          homeConfigurations = mylib.mkHomeConfigurations (
            self.darwinConfigurations // self.nixosConfigurations
          );
        };
      };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-darwin.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    import-tree.url = "github:denful/import-tree";
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs-darwin";
    };
    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko/v1.13.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    catppuccin = {
      url = "github:catppuccin/nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    vgpu4nixos = {
      url = "github:shelken/vgpu4nixos";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    secrets = {
      url = "git+https://github.com/shelken/secrets.nix.git?shallow=1";
      flake = false;
    };

    # 钉 release tag：main 上的提交可能领先已发布的二进制
    openwrt-nix = {
      url = "github:lonerOrz/openwrt-nix/v0.1.2";
      flake = false;
    };

    # 用 git+https 而不是 github:：github fetcher 拒绝同时给 ref 与 rev，而 Renovate 要靠两者开 digest PR。
    anti-slop = {
      url = "git+https://github.com/dmmulroy/anti-slop?ref=main&rev=63dbb09f73438e550a6991dc6d778f979ffbf183&shallow=1";
      flake = false;
    };
    caldo-skills = {
      url = "git+https://github.com/caldoai/skills?ref=main&rev=d5b68dace378219890d821adb3685538e2c69b04&shallow=1";
      flake = false;
    };
    cursor-plugins = {
      url = "git+https://github.com/cursor/plugins?ref=main&rev=aaeb0ea3a0584995aa8f55ce44c6c5259414b896&shallow=1";
      flake = false;
    };
    diagram-design = {
      url = "git+https://github.com/cathrynlavery/diagram-design?ref=main&rev=d74d8c2d0c78a9e1efd43137f6a9a51182a8b5f0&shallow=1";
      flake = false;
    };
    humanlayer-skills = {
      url = "git+https://github.com/humanlayer/skills?ref=main&rev=4d69d20f6e9b57b4fcf0d501ccfb1be961f0f329&shallow=1";
      flake = false;
    };
    improve = {
      url = "git+https://github.com/shadcn/improve?ref=main&rev=cac56e1ebd3c279aa9153616cfeac7b174ab90f9&shallow=1";
      flake = false;
    };
    kitty-icon = {
      url = "git+https://github.com/DinkDonk/kitty-icon?ref=main&rev=b0108d7d4059164744eadd57ed644a7b2808ed3b&shallow=1";
      flake = false;
    };
    llamaparse-agent-skills = {
      url = "git+https://github.com/run-llama/llamaparse-agent-skills?ref=main&rev=2dcef7c62417bd2ec4671fce4621bb1e8cce48d0&shallow=1";
      flake = false;
    };
    mattpocock-skills = {
      url = "git+https://github.com/mattpocock/skills?ref=main&rev=abeeaf95660ba9e8b7c753eb38f441ca707a8823&shallow=1";
      flake = false;
    };
    rime-main = {
      url = "git+https://github.com/iDvel/rime-ice?ref=main&rev=927e1cf1d3eeb9bf4be85e3f684dba4dd485b6f6&shallow=1";
      flake = false;
    };
    security-audit-skill = {
      url = "git+https://github.com/cloudflare/security-audit-skill?ref=main&rev=c1c8a8c1471069fb0e188eeaff69b8e8db6564a8&shallow=1";
      flake = false;
    };
    swipt-skills = {
      url = "git+https://github.com/swipt-automation/skills?ref=main&rev=8edabfa0444ad5c4a03ad045d0c0641b157ef7b6&shallow=1";
      flake = false;
    };
  };
}
