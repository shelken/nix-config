# nix 周边工具：zmx、nix-melt、nix-tree、nix-output-monitor
{ config, ... }:
{
  flake.modules.homeManager.core.imports = [ config.flake.modules.homeManager.nix-tools ];

  flake.modules.homeManager.nix-tools =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        zmx
        # nix tool
        # https://github.com/nix-community/nix-melt
        nix-melt # A TUI flake.lock viewer
        # https://github.com/utdemir/nix-tree
        nix-tree # A TUI to visualize the dependency graph of a nix derivation
        nix-output-monitor # nom
      ];
    };
}
