# Hyprland 合成器
# 可选功能，需要时主机 imports = [ self.modules.nixos.hyprland ]
# 仓库默认桌面是 niri（features/gui/niri.nix），两者不要同时启用
{
  flake.modules.nixos.hyprland.programs.hyprland = {
    enable = true;

    xwayland.enable = true;
  };
}
