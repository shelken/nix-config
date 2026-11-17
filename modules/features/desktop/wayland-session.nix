# Wayland 用户会话：桌面环境变量、剪贴板、锁屏、注销菜单、通知守护
# 只适用 Linux → 仅 nixos.gui
{ config, ... }:
{
  flake.modules.nixos.gui.imports = [ config.flake.modules.nixos.wayland-session ];

  flake.modules.homeManager.wayland-session =
    { pkgs, ... }:
    {
      # wayland related
      home.sessionVariables = {
        "NIXOS_OZONE_WL" = "1"; # for any ozone-based browser & electron apps to run on wayland
        "MOZ_ENABLE_WAYLAND" = "1"; # for firefox to run on wayland
        "MOZ_WEBRENDER" = "1";
        # enable native Wayland support for most Electron apps
        "ELECTRON_OZONE_PLATFORM_HINT" = "auto";
        # misc
        "_JAVA_AWT_WM_NONREPARENTING" = "1";
        "QT_WAYLAND_DISABLE_WINDOWDECORATION" = "1";
        "QT_QPA_PLATFORM" = "wayland";
        "SDL_VIDEODRIVER" = "wayland";
        "GDK_BACKEND" = "wayland";
        "XDG_SESSION_TYPE" = "wayland";
      };

      home.packages = with pkgs; [
        # swaybg # the wallpaper
        wl-clipboard # copying and pasting
      ];

      # screen locker
      programs.swaylock.enable = true;

      # Logout Menu
      programs.wlogout.enable = true;

      # notification daemon, the same as dunst
      services.mako.enable = true;
    };
}
