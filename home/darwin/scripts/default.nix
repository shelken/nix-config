{pkgs, ...} @ args: let
  idea = import ./idea.nix {inherit pkgs;};
  reset-fcp-trail = import ./reset-fcp-trail.nix {inherit pkgs;};
in {
  imports = [
    ./raycast.nix
  ];
  home.packages = [
    idea.script
    reset-fcp-trail.script
  ];
}
