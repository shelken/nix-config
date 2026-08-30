{ pkgs, ... }:
let
  idea = import ./idea.nix { inherit pkgs; };
  loon-ctl = import ./loon-ctl.nix { inherit pkgs; };
  reset-fcp-trial = import ./reset-fcp-trial.nix { inherit pkgs; };
in
{
  imports = [
    ./raycast.nix
  ];
  home.packages = [
    idea.script
    loon-ctl.script
    reset-fcp-trial.script
  ];
}
