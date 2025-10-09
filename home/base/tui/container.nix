{ pkgs, ... }:
{
  home.packages = with pkgs; [
  ];

  programs.k9s.enable = true;
  # catppuccin.k9s.transparent = true;

  programs.kubecolor = {
    enable = true;
    enableAlias = true;
  };
}
