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

    # nix communities cache server
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
      secrets,
      flake-parts,
      ...
    }:
    let
      inherit (inputs.nixpkgs) lib;
      myvars = import ./vars { inherit lib; };
      mylib = import ./lib { inherit lib secrets myvars; };

      genSpecialArgs =
        nixpkgsInput: system:
        let
          pkgs = import nixpkgsInput {
            inherit system;
            config.allowUnfree = true;
          };
        in
        inputs
        // {
          # 主输入即 unstable channel；HM 模块沿用 pkgs-unstable 变量名，与 pkgs 同源
          pkgs-unstable = pkgs;

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
        # Ubuntu → NixOS 接管后的美国 VPS；放在 hosts/vps/ 下，所有 VPS 统一归这里
        vps-cc = mkHost {
          type = "nixos";
          system = "x86_64-linux";
          # root + 密钥部署：激活不需要口令，也不必给 shelken 配免密 sudo
          deploy = {
            sshUser = "root";
            interactiveSudo = false;
          };
          nixos-modules = map mylib.relativeToRoot [
            "hosts/vps/vps-cc"
          ];
        };
        # vps-cc 的 x86_64 BIOS 演练机（Lima + qemu）
        vps-test = mkHost {
          type = "nixos";
          system = "x86_64-linux";
          nixos-modules = map mylib.relativeToRoot [
            "hosts/vm/vps-test"
          ];
        };
        # Lima 里的 Ubuntu → NixOS 接管演练机（nixos-anywhere + disko + facter）
        # 放在 hosts/vm/ 下不新增 hosts/ 顶层目录，不影响 calcUniformSchedule 的备份时段
        lima-test = mkHost {
          type = "nixos";
          system = "aarch64-linux";
          nixos-modules = map mylib.relativeToRoot [
            "hosts/vm/lima-test"
          ];
        };
        work-test = mkHost {
          type = "nixos";
          system = "x86_64-linux";
          # 无硬件配置的求值测试机，不建 hosts 目录：calcUniformSchedule 按 hosts/ 目录数排定备份时段
          nixos-modules = [ self.modules.nixos.tui ];
        };
        yuuko = mkHost {
          type = "darwin";
          system = "aarch64-darwin";
          deploy = true;
          darwin-modules = map mylib.relativeToRoot [
            "hosts/yuuko"
          ];
          home-modules = map mylib.relativeToRoot [
            "hosts/yuuko/home.nix"
          ];
        };
        sakamoto = mkHost {
          type = "darwin";
          system = "aarch64-darwin";
          deploy = true;
          darwin-modules = map mylib.relativeToRoot [
            "hosts/sakamoto"
          ];
          home-modules = map mylib.relativeToRoot [
            "hosts/sakamoto/home.nix"
          ];
        };
        mio = mkHost {
          type = "darwin";
          system = "aarch64-darwin";
          darwin-modules = map mylib.relativeToRoot [
            "hosts/mio"
          ];
          home-modules = map mylib.relativeToRoot [
            "hosts/mio/home.nix"
          ];
        };
        ling = mkHost {
          type = "darwin";
          system = "aarch64-darwin";
          deploy = true;
          darwin-modules = map mylib.relativeToRoot [
            "hosts/ling"
          ];
          home-modules = map mylib.relativeToRoot [
            "hosts/ling/home.nix"
          ];
        };
      };

      darwinHosts = lib.filterAttrs (_: v: v.type == "darwin") hosts;
      nixosHosts = lib.filterAttrs (_: v: v.type == "nixos") hosts;

      # deploy 为 true 或带参数的属性集都算部署目标
      deployHosts = lib.filterAttrs (_: v: (v.deploy or false) != false) hosts;
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      # 同名即同一功能：一个功能的 darwin / homeManager / nixos 部分写在同一文件或同一目录；
      # 路径含 /_ 的文件不自动导入，用于数据或私有片段
      imports = [
        flake-parts.flakeModules.modules
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
        nixosConfigurations = lib.mapAttrs (_: v: mylib.nixosSystem v) nixosHosts;
        darwinConfigurations = lib.mapAttrs (_: v: mylib.macosSystem v) darwinHosts;
        # Home 不是第二套配置，只导出系统结果中已经求值的 Home 子配置：
        # config 指向它，activationPackage 指向同一个 derivation，
        # 供 `nh home build/switch -c <host>` 读取（nh 走 config.home.activationPackage）。
        homeConfigurations = lib.mapAttrs (
          name: host:
          let
            systemConfig =
              if host.type == "darwin" then
                self.darwinConfigurations.${name}
              else if host.type == "nixos" then
                self.nixosConfigurations.${name}
              else
                throw "Unsupported Home host type: ${host.type}";

            hm = systemConfig.config.home-manager.users.${myvars.username};

            # 与上游 homeManagerConfiguration 等价的断言/告警检查，避免请求 Home 时静默跳过失败断言
            failed = map (x: x.message) (lib.filter (x: !x.assertion) hm.assertions);
            checkedHome =
              if failed != [ ] then
                throw ''
                  Failed assertions:
                  ${lib.concatStringsSep "\n" (map (x: "- ${x}") failed)}''
              else
                lib.foldr (warning: result: builtins.trace "warning: ${warning}" result) hm hm.warnings;
          in
          {
            config = checkedHome;
            activationPackage = checkedHome.home.activationPackage;
          }
        ) hosts;

        # deploy-rs 远程部署：hosts 中标记 `deploy = true`（或 attrset 透传参数）的主机自动生成节点
        deploy = {
          nodes = lib.mapAttrs (
            name: v:
            mylib.deployNode {
              deploy-rs = inputs.deploy-rs;
              inherit name;
              configuration =
                if v.type == "darwin" then self.darwinConfigurations.${name} else self.nixosConfigurations.${name};
              inherit (v) type system;
              extra = if builtins.isAttrs v.deploy then v.deploy else { };
            }
          ) deployHosts;
        };
      };

      perSystem =
        {
          config,
          pkgs,
          system,
          ...
        }:
        {
          checks = {
            #ref: https://devenv.sh/?q=git-hooks.hooks
            pre-commit-check = inputs.git-hooks.lib.${system}.run {
              src = ./.;
              hooks = {
                #NOTE 目前不支持配置垂直对其
                nixfmt = {
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
            # deploy-rs 部署配置校验（schema/激活脚本检查）；
            # 只在原生系统启用，跨系统会让 nix flake check 尝试交叉构建
          }
          // lib.optionalAttrs (system == "aarch64-darwin") (
            inputs.deploy-rs.lib.${system}.deployChecks self.deploy
          );

          # Development Shells
          devShells.default = pkgs.mkShellNoCC {
            packages = with pkgs; [
              # fix https://discourse.nixos.org/t/non-interactive-bash-errors-from-flake-nix-mkshell/33310
              bashInteractive
              # deploy
              deploy-rs
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
              actionlint
              # nh # 不要引入，会把nix放进来
              # nix-prefetch-github # 已由 utils/script/prefetch 替代
              # nix-prefetch-git # 已由 utils/script/prefetch 替代
            ];
            name = "dots";
            shellHook = ''
              ${config.checks.pre-commit-check.shellHook}
            '';
          };

          # nixfmt-tree: treefmt 包装,支持目录参数;裸 nixfmt 传目录已被 Nix 标记 deprecated
          formatter = pkgs.nixfmt-tree;
        };
    };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    # 递归导入 modules/{flake,features,profiles} 下的 flake-parts 模块（路径含 /_ 的忽略）
    import-tree.url = "github:denful/import-tree";
    # 与 nixpkgs 同分支却独立锁定，只会漂移出第二份源码树；收敛为别名
    nixpkgs-unstable.follows = "nixpkgs";
    # darwin 走 nixpkgs-unstable 分支：发布不等 NixOS 测试套件，
    # darwin 修复不被 NixOS 测试失败阻塞；nix-darwin 官方示例同款
    nixpkgs-darwin.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin";
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
      url = "git+https://github.com/shelken/secrets.nix.git?shallow=1";
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

    # deploy-rs 远程部署
    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # disko
    disko = {
      url = "github:nix-community/disko/v1.13.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # git-hooks; gen pre-commit-config
    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    niri = {
      url = "github:sodiboo/niri-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

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
  };
}
