{ pkgs, ... }:
{
  home.packages = with pkgs; [
    dive # A tool for exploring each layer in a docker image
    lazydocker # docker管理
  ];

  programs.k9s.enable = true;
  # catppuccin.k9s.transparent = true;

  programs.kubecolor = {
    enable = true;
    enableAlias = true;
  };
}
