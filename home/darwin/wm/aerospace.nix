{
  lib,
  mylib,
  config,
  # options,
  ...
}:
let
  inherit (lib) mkIf;
  inherit (mylib) mkBoolOpt;
  cfg = config.shelken.wm.aerospace;
  aerospaceTomlPath = "${config.home.homeDirectory}/nix-config/home/darwin/wm/aerospace/aerospace.toml";
in
{
  options.shelken.wm.aerospace = {
    enable = mkBoolOpt false "Whether or not to enable aerospace.";
  };

  config = mkIf cfg.enable {
    xdg.configFile = {
      "aerospace/aerospace.toml" = {
        source = config.lib.file.mkOutOfStoreSymlink aerospaceTomlPath;
        force = true;
      };
      "aerospace/scripts/pip-move.sh" = {
        # source = ./aerospace/scripts;
        text = ''
          #!/usr/bin/env bash
          set -e
          # Get current workspace
          current_workspace=$(aerospace list-workspaces --focused)
          # Move PiP windows to current workspace (handles both "Picture-in-Picture" and "Picture in Picture")
          aerospace list-windows --all | grep -E "(\| Picture-in-Picture|\| Picture in Picture|\| 画中画|\| Raycast)" | awk '{print $1}' | while read window_id; do
              if [ -n "$window_id" ]; then
                  aerospace move-node-to-workspace --window-id "$window_id" "$current_workspace"
              fi
          done
        '';
        force = true;
        executable = true;
      };
      "aerospace/scripts/open-terminal-in-finder-path.sh" = {
        text = ''
          #!/usr/bin/env bash
          osascript -e '
            if application "Finder" is not running then
              return "Not running"
            end if

            tell application "Finder"
              set pathList to (POSIX path of ((insertion location) as alias))
            end tell
            set command to "open -a kitty"
            do shell script command

            set the clipboard to pathList

            tell application "System Events"
              # new tab
              keystroke "t" using {command down}
              # cd "thePath" return;
              keystroke "cd \""
              keystroke "v" using {command down}
              keystroke "\""
              keystroke return
              # clean screen
              keystroke "l" using {control down}
            end tell
          '
        '';
        force = true;
        executable = true;
      };
      "aerospace/scripts/get-app-bundleid.sh" = {
        text = ''
          #!/usr/bin/env bash
          osascript -e '
            tell application "System Events" to set frontAppId to bundle identifier of first process whose frontmost is true
            set the clipboard to frontAppId
            tell application "System Events" to display alert "已复制到剪贴板" message frontAppId buttons {""} default button "" giving up after 2
          '
        '';
        force = true;
        executable = true;
      };
    };
  };
}
