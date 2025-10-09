{ ... }:
{
  wayland.windowManager.hyprland = {
    enable = false;
    # extraConfig = builtins.readFile ./hypr/hyprland.conf;
    # systemd.enable = true;
  };
  #
  imports = [
    # ./wayland-apps.nix
    # ./packages.nix
  ];
  xdg.configFile = {
    # "dunst" = {
    #   source = ./dunst;
    #   recursive = true;
    # };
    # "cava" = {
    #   source = ./cava;
    #   recursive = true;
    # };
    # "rofi" = {
    #   source = ./rofi;
    #   recursive = true;
    # };
    # "waybar" = {
    #   source = ./waybar;
    #   recursive = true;
    # };
    # "hypr" = {
    #   source = ./hypr;
    #   recursive = true;
    # };
  };
}
