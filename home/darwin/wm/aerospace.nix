{
  lib,
  mylib,
  config,
  # options,
  ...
}: let
  inherit (lib) mkIf;
  inherit (mylib) mkBoolOpt;
  cfg = config.shelken.wm.aerospace;
in {
  options.shelken.wm.aerospace = {
    enable = mkBoolOpt false "Whether or not to enable aerospace.";
  };

  config = mkIf cfg.enable {
    xdg.configFile = {
      "aerospace/aerospace.toml" = {
        source = ./aerospace/aerospace.toml;
      };
      "aerospace/scripts/pip-move.sh" = {
        # source = ./aerospace/scripts;
        text = ''
          #!/usr/bin/env bash
          set -e
          # Get current workspace
          current_workspace=$(aerospace list-workspaces --focused)
          # Move PiP windows to current workspace (handles both "Picture-in-Picture" and "Picture in Picture")
          aerospace list-windows --all | grep -E "(\| Picture-in-Picture|\| Picture in Picture|\| 画中画|\| 访达|\| Raycast)" | awk '{print $1}' | while read window_id; do
              if [ -n "$window_id" ]; then
                  aerospace move-node-to-workspace --window-id "$window_id" "$current_workspace"
              fi
          done
        '';
        force = true;
        executable = true;
      };
    };
  };
}
