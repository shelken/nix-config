# FHS 环境与 nix-ld：运行非 NixOS 的预编译程序（flatpak 之外的 appimage 等）
# NixOS 桌面机 → nixos.gui
{ config, ... }:
{
  flake.modules.nixos.gui.imports = [ config.flake.modules.nixos.fhs ];

  flake.modules.nixos.fhs =
    { lib, pkgs, ... }:
    {
      # mkOrder：保持迁移前 fhs 在桌面包之前
      environment.systemPackages = lib.mkOrder 630 [
        # create a fhs environment by command `fhs`, so we can run non-nixos packages in nixos!
        (
          let
            base = pkgs.appimageTools.defaultFhsEnvArgs;
          in
          pkgs.buildFHSEnv (
            base
            // {
              name = "fhs";
              targetPkgs = pkgs: (base.targetPkgs pkgs) ++ [ pkgs.pkg-config ];
              profile = "export FHS=1";
              runScript = "bash";
              extraOutputsToInstall = [ "dev" ];
            }
          )
        )
      ];

      # https://github.com/Mic92/nix-ld
      #
      # nix-ld will install itself at `/lib64/ld-linux-x86-64.so.2` so that
      # it can be used as the dynamic linker for non-NixOS binaries.
      #
      # nix-ld's nixos module will set default values for `NIX_LD` and `NIX_LD_LIBRARY_PATH` environment variables, so
      # it can work out of the box:
      #
      #  - https://github.com/NixOS/nixpkgs/blob/nixos-25.11/nixos/modules/programs/nix-ld.nix#L37-L40
      #
      # You can overwrite `NIX_LD_LIBRARY_PATH` in the environment where you run the non-NixOS binaries to customize the
      # search path for shared libraries.
      programs.nix-ld = {
        enable = true;
        libraries = with pkgs; [
          stdenv.cc.cc
        ];
      };
    };
}
