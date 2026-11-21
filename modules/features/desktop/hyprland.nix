{
  flake.modules.nixos.hyprland.programs.hyprland = {
    enable = true;

    xwayland.enable = true;
  };
}
