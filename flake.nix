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
      url = "git+https://github.com/dmmulroy/anti-slop?ref=main&rev=13909c9e07590f5a85d93c62712259fe14a883f7&shallow=1";
      flake = false;
    };
    caldo-skills = {
      url = "git+https://github.com/caldoai/skills?ref=main&rev=f3cf47774975a7d9fca45730babf4ff7ad765ada&shallow=1";
      flake = false;
    };
    cursor-plugins = {
      url = "git+https://github.com/cursor/plugins?ref=main&rev=6b0300214a09fd6029cfb7077043125758cd1fd2&shallow=1";
      flake = false;
    };
    diagram-design = {
      url = "git+https://github.com/cathrynlavery/diagram-design?ref=main&rev=e57eda6102a19444538ebd611d39534fad65b663&shallow=1";
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
      url = "git+https://github.com/mattpocock/skills?ref=main&rev=4ae2317ddb22b046e26455e4f9c9b3aaaf62212d&shallow=1";
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
