{pkgs, ...} @ args: let
  idea = import ./idea.nix {inherit pkgs;};
in {
  home.packages = [
    idea.idea_open_folder
  ];
}
