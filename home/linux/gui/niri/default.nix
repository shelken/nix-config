{
  pkgs,
  config,
  lib,
  niri,
  ...
} @ args: let
  settings = {};
in {
  config = (
    lib.mkMerge [
      {
        home.packages = with pkgs; [
          # Niri v25.08 will create X11 sockets on disk, export $DISPLAY, and spawn `xwayland-satellite` on-demand when an X11 client connects
          xwayland-satellite
        ];

        # programs.niri.enable = true;
        # programs.niri.config = settings;

        # NOTE: this executable is used by greetd to start a wayland session when system boot up
        # with such a vendor-no-locking script, we can switch to another wayland compositor without modifying greetd's config in NixOS module
        home.file.".wayland-session" = {
          source = pkgs.writeScript "init-session" ''
            # trying to stop a previous niri session
            systemctl --user is-active niri.service && systemctl --user stop niri.service
            # and then we start a new one
            /run/current-system/sw/bin/niri-session
          '';
          executable = true;
        };
      }
      # (import ./settings.nix niri)
      (import ./keybindings.nix niri)
      # (import ./spawn-at-startup.nix niri)
      # (import ./windowrules.nix niri)
    ]
  );
}
