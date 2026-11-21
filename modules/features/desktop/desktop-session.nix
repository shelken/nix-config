{ config, ... }:
{
  flake.modules.nixos.gui.imports = [ config.flake.modules.nixos.desktop-session ];

  flake.modules.nixos.desktop-session =
    {
      config,
      lib,
      pkgs,
      myvars,
      ...
    }:
    {
      xdg.portal = {
        enable = true;

        config = {
          common = {
            default = [ "gtk" ];
            "org.freedesktop.impl.portal.Secret" = [ "gnome-keyring" ];
          };
        };

        xdgOpenUsePortal = true;

        extraPortals = lib.mkBefore (
          with pkgs;
          [
            xdg-desktop-portal-gtk
          ]
        );
      };

      services = {
        xserver.enable = false;
        greetd = {
          enable = true;
          settings.default_session = {
            user = myvars.username;
            command = config.shelken.desktop.sessionCommand;
          };
        };
      };

      boot.loader.timeout = lib.mkForce 10;

      environment.shells = with pkgs; [
        bashInteractive
        nushell
      ];
      users.defaultUserShell = pkgs.bashInteractive;

      environment.systemPackages = with pkgs; [
        gnumake
        wl-clipboard
      ];

      services.gvfs.enable = true;
      services.tumbler.enable = true;

      programs.dconf.enable = true;

      programs.thunar = {
        enable = true;
        plugins = with pkgs.xfce; [
          thunar-archive-plugin
          thunar-volman
        ];
      };

      security.sudo.keepTerminfo = true;
    };
}
