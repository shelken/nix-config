{ pkgs, ... }:
let
  idea = import ./idea.nix { inherit pkgs; };
  reset-fcp-trial = import ./reset-fcp-trial.nix { inherit pkgs; };
in
{
  imports = [
    ./raycast.nix
  ];
  home.packages = [
    idea.script
    reset-fcp-trial.script
  ];
}
