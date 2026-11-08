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
      hosts = import ./hosts { inherit self; };

      darwinHosts = lib.filterAttrs (_: v: v.type == "darwin") hosts;
      nixosHosts = lib.filterAttrs (_: v: v.type == "nixos") hosts;
    in
    inputs.flake-parts.lib.mkFlake
      {
        inherit inputs;
        specialArgs = { inherit mylib hosts; };
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
    # 走 nixpkgs-unstable 分支：发布不等 NixOS 测试套件，darwin 修复不被 NixOS 测试失败阻塞
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

    anyrun = {
      url = "github:anyrun-org/anyrun/v25.9.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    catppuccin = {
      url = "github:catppuccin/nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    niri = {
      url = "github:sodiboo/niri-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    dotfiles = {
      url = "github:shelken/dotfiles.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    secrets = {
      url = "git+https://github.com/shelken/secrets.nix.git?shallow=1";
      flake = false;
    };

    # 静态资源（flake = false）：他人维护、只锁版本的文件树，见 docs/adr/0006-static-assets-as-flake-inputs.md。
    # 用 git+https 而不是 github:：github fetcher 拒绝同时给 ref 与 rev，而 Renovate 要靠两者开 digest PR。
    anti-slop = {
      url = "git+https://github.com/dmmulroy/anti-slop?ref=main&rev=e8c4880471b23ab7f216fba7b27d173a6ef07d4c&shallow=1";
      flake = false;
    };
    caldo-skills = {
      url = "git+https://github.com/caldoai/skills?ref=main&rev=f3cf47774975a7d9fca45730babf4ff7ad765ada&shallow=1";
      flake = false;
    };
    cursor-plugins = {
      url = "git+https://github.com/cursor/plugins?ref=main&rev=6f6c9e62585436f69e560138d46709026fa5c69f&shallow=1";
      flake = false;
    };
    diagram-design = {
      url = "git+https://github.com/cathrynlavery/diagram-design?ref=main&rev=cdfdc9686cd7465da70b68b036581833b503810c&shallow=1";
      flake = false;
    };
    humanlayer-skills = {
      url = "git+https://github.com/humanlayer/skills?ref=main&rev=653b6411c1f70c275a18e37673b042ff99f67ceb&shallow=1";
      flake = false;
    };
    kitty-icon = {
      url = "git+https://github.com/DinkDonk/kitty-icon?ref=main&rev=b0108d7d4059164744eadd57ed644a7b2808ed3b&shallow=1";
      flake = false;
    };
    llamaparse-agent-skills = {
      url = "git+https://github.com/run-llama/llamaparse-agent-skills?ref=main&rev=a8d8b34ad6a815ba3257f921c5eccc9ca95e429f&shallow=1";
      flake = false;
    };
    mattpocock-skills = {
      url = "git+https://github.com/mattpocock/skills?ref=main&rev=59db609eb1e18aaf59b63284d0e52255aff0c63c&shallow=1";
      flake = false;
    };
    rime-main = {
      url = "git+https://github.com/iDvel/rime-ice?ref=main&rev=99662ba01e3affa6a0f009174ca530b887bac3b6&shallow=1";
      flake = false;
    };
    security-audit-skill = {
      url = "git+https://github.com/cloudflare/security-audit-skill?ref=main&rev=c1c8a8c1471069fb0e188eeaff69b8e8db6564a8&shallow=1";
      flake = false;
    };
  };
}
