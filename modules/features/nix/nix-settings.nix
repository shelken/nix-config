{ config, lib, ... }:
{
  flake.modules.nixos.core.imports = [ config.flake.modules.nixos.nix-settings ];
  flake.modules.darwin.core.imports = [ config.flake.modules.darwin.nix-settings ];

  flake.modules.nixos.nix-settings =
    { myvars, pkgs, ... }:
    {
      nix.package = pkgs.nix;

      nixpkgs.config.allowUnfree = lib.mkForce true;

      nix.settings.auto-optimise-store = true;

      nix.channel.enable = false;

      nix.settings = {
        experimental-features = [
          "nix-command"
          "flakes"
        ];

        trusted-users = [ myvars.username ];

        substituters = [

          "https://nix-community.cachix.org"
        ];

        trusted-public-keys = [
          "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        ];
        builders-use-substitutes = true;
      };
    };

  flake.modules.darwin.nix-settings =
    {
      lib,
      inputs,
      ...
    }:
    {
      nix.enable = false;

      # 注意：Determinate 主 nix.conf 在 !include 之后又设了 extra-substituters，
      # 会覆盖此处的 extra-substituters（nix #9487）。所以 substituters 必须用
      # 覆盖语义写全完整列表（主文件不设基础 substituters，覆盖不破坏默认）；
      # trusted-public-keys 主文件用 extra- 追加，这里也用 extra- 追加即可。
      environment.etc."nix/nix.custom.conf".text = ''
        substituters = https://cache.nixos.org https://nix-community.cachix.org https://install.determinate.systems
        extra-trusted-public-keys = nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=
        fallback = true
        connect-timeout = 2
        filetransfer-retry-attempts = 1
        builders-use-substitutes = true
        trusted-users = shelken nixos
        # Linux 构建由 Determinate 的 Native Linux Builder 提供，这里不配 builders / extra-platforms：
        # external-builders 由 determinate-nixd 写入 /etc/nix/nix.conf，手写会绕过开通检查。
      '';

      # EXTERNAL: Determinate Nix（nix.enable = false）下 nix-darwin 不接管 registry，需手写 /etc/nix/registry.json 锁定 nixpkgs-darwin；且其 getRegistries() 仍先调 getGlobalRegistry()，无法彻底屏蔽远端查询
      environment.etc."nix/registry.json".text = builtins.toJSON {
        version = 2;
        flakes = [
          {
            from = {
              type = "indirect";
              id = "nixpkgs";
            };
            to = {
              type = "path";
              path = toString inputs.nixpkgs-darwin;
            }
            // lib.filterAttrs (
              n: _: n == "lastModified" || n == "rev" || n == "revCount" || n == "narHash"
            ) inputs.nixpkgs-darwin;
            exact = true;
          }
        ];
      };

    };
}
