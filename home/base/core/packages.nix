{ pkgs, ... }:
{
  home.packages = with pkgs; [
    # nix tool
    # https://github.com/nix-community/nix-melt
    nix-melt # A TUI flake.lock viewer
    # https://github.com/utdemir/nix-tree
    nix-tree # A TUI to visualize the dependency graph of a nix derivation
    nix-output-monitor # nom
  ];
}
