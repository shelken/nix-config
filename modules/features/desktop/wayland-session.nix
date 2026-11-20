{ config, ... }:
let
  sessionFile = ".wayland-session";
in
{
  flake.modules.nixos.gui.imports = [ config.flake.modules.nixos.wayland-session ];

  flake.modules.nixos.wayland-session =
    { lib, ... }:
    {
      options.shelken.desktop.sessionCommand = lib.mkOption {
        type = lib.types.str;
        readOnly = true;
        default = "$HOME/${sessionFile}";
      };
    };

  flake.modules.homeManager.wayland-session =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      options.shelken.desktop.sessionScript = lib.mkOption {
        type = lib.types.path;
      };

      config = {
        home.file.${sessionFile} = {
          source = config.shelken.desktop.sessionScript;
          executable = true;
        };

        home.sessionVariables = {
          "NIXOS_OZONE_WL" = "1";
          "MOZ_ENABLE_WAYLAND" = "1";
          "MOZ_WEBRENDER" = "1";
          "ELECTRON_OZONE_PLATFORM_HINT" = "auto";
          "_JAVA_AWT_WM_NONREPARENTING" = "1";
          "QT_WAYLAND_DISABLE_WINDOWDECORATION" = "1";
          "QT_QPA_PLATFORM" = "wayland";
          "SDL_VIDEODRIVER" = "wayland";
          "GDK_BACKEND" = "wayland";
          "XDG_SESSION_TYPE" = "wayland";
        };

        home.packages = with pkgs; [
          wl-clipboard
        ];

        programs.swaylock.enable = true;

        programs.wlogout.enable = true;

        services.mako.enable = true;
      };
    };
}
