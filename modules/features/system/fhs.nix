{ config, ... }:
{
  flake.modules.nixos.gui.imports = [ config.flake.modules.nixos.fhs ];

  flake.modules.nixos.fhs =
    { pkgs, ... }:
    {
      environment.systemPackages = [
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

      # nix-ld's nixos module will set default values for `NIX_LD` and `NIX_LD_LIBRARY_PATH` environment variables, so
      # it can work out of the box:
      programs.nix-ld = {
        enable = true;
        libraries = with pkgs; [
          stdenv.cc.cc
        ];
      };
    };
}
