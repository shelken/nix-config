# 可选功能，需要时主机 imports = [ self.modules.nixos.hyprland ]
{
  flake.modules.nixos.hyprland.programs.hyprland = {
    enable = true;

    xwayland.enable = true;
  };
}
