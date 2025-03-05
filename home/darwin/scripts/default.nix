{pkgs, ...} @ args: let
  idea = import ./idea.nix {inherit pkgs;};
in {
  imports = [
    ./raycast.nix
  ];
  home.packages = [
    idea.idea_open_folder
  ];
}
