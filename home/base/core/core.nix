{pkgs, ...}: {
  home.packages = with pkgs; [
    lazygit
    just
    zoxide
  ];
}
