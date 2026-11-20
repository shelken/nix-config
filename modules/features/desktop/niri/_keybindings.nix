niri: {
  programs.niri.config =
    let
      inherit (niri.lib.kdl)
        plain
        leaf
        flag
        ;
    in
    [
      (plain "binds" [
        # "Mod" is a special modifier equal to Super when running on a TTY, and to Alt
        # when running as a winit window.

        (plain "Mod+Shift+Slash" [ (flag "show-hotkey-overlay") ])

        (plain "Mod+Return" [ (leaf "spawn" [ "foot" ]) ])
        (plain "Mod+Shift+Return" [ (leaf "spawn" [ "alacritty" ]) ])
        (plain "Mod+D" [ (leaf "spawn" [ "anyrun" ]) ])
        (plain "CTRL+Alt+L" [ (leaf "spawn" [ "swaylock" ]) ])

        (plain "XF86AudioRaiseVolume" [
          (leaf "spawn" [
            "wpctl"
            "set-volume"
            "@DEFAULT_AUDIO_SINK@"
            "0.1+"
          ])
        ])
        (plain "XF86AudioLowerVolume" [
          (leaf "spawn" [
            "wpctl"
            "set-volume"
            "@DEFAULT_AUDIO_SINK@"
            "0.1-"
          ])
        ])

        (plain "Mod+Q" [ (flag "close-window") ])

        (plain "Mod+Left" [ (flag "focus-column-left") ])
        (plain "Mod+Down" [ (flag "focus-window-down") ])
        (plain "Mod+Up" [ (flag "focus-window-up") ])
        (plain "Mod+Right" [ (flag "focus-column-right") ])
        (plain "Mod+H" [ (flag "focus-column-left") ])
        (plain "Mod+J" [ (flag "focus-window-down") ])
        (plain "Mod+K" [ (flag "focus-window-up") ])
        (plain "Mod+L" [ (flag "focus-column-right") ])

        (plain "Mod+Ctrl+Left" [ (flag "move-column-left") ])
        (plain "Mod+Ctrl+Down" [ (flag "move-window-down") ])
        (plain "Mod+Ctrl+Up" [ (flag "move-window-up") ])
        (plain "Mod+Ctrl+Right" [ (flag "move-column-right") ])
        (plain "Mod+Ctrl+H" [ (flag "move-column-left") ])
        (plain "Mod+Ctrl+J" [ (flag "move-window-down") ])
        (plain "Mod+Ctrl+K" [ (flag "move-window-up") ])
        (plain "Mod+Ctrl+L" [ (flag "move-column-right") ])

        (plain "Mod+Home" [ (flag "focus-column-first") ])
        (plain "Mod+End" [ (flag "focus-column-last") ])
        (plain "Mod+Ctrl+Home" [ (flag "move-column-to-first") ])
        (plain "Mod+Ctrl+End" [ (flag "move-column-to-last") ])

        (plain "Mod+Shift+Left" [ (flag "focus-monitor-left") ])
        (plain "Mod+Shift+Down" [ (flag "focus-monitor-down") ])
        (plain "Mod+Shift+Up" [ (flag "focus-monitor-up") ])
        (plain "Mod+Shift+Right" [ (flag "focus-monitor-right") ])
        (plain "Mod+Shift+H" [ (flag "focus-monitor-left") ])
        (plain "Mod+Shift+J" [ (flag "focus-monitor-down") ])
        (plain "Mod+Shift+K" [ (flag "focus-monitor-up") ])
        (plain "Mod+Shift+L" [ (flag "focus-monitor-right") ])

        (plain "Mod+Shift+Ctrl+Left" [ (flag "move-column-to-monitor-left") ])
        (plain "Mod+Shift+Ctrl+Down" [ (flag "move-column-to-monitor-down") ])
        (plain "Mod+Shift+Ctrl+Up" [ (flag "move-column-to-monitor-up") ])
        (plain "Mod+Shift+Ctrl+Right" [ (flag "move-column-to-monitor-right") ])
        (plain "Mod+Shift+Ctrl+H" [ (flag "move-column-to-monitor-left") ])
        (plain "Mod+Shift+Ctrl+J" [ (flag "move-column-to-monitor-down") ])
        (plain "Mod+Shift+Ctrl+K" [ (flag "move-column-to-monitor-up") ])
        (plain "Mod+Shift+Ctrl+L" [ (flag "move-column-to-monitor-right") ])

        (plain "Mod+Page_Down" [ (flag "focus-workspace-down") ])
        (plain "Mod+Page_Up" [ (flag "focus-workspace-up") ])
        (plain "Mod+U" [ (flag "focus-workspace-down") ])
        (plain "Mod+I" [ (flag "focus-workspace-up") ])
        (plain "Mod+Ctrl+Page_Down" [ (flag "move-column-to-workspace-down") ])
        (plain "Mod+Ctrl+Page_Up" [ (flag "move-column-to-workspace-up") ])
        (plain "Mod+Ctrl+U" [ (flag "move-column-to-workspace-down") ])
        (plain "Mod+Ctrl+I" [ (flag "move-column-to-workspace-up") ])

        (plain "Mod+Shift+Page_Down" [ (flag "move-workspace-down") ])
        (plain "Mod+Shift+Page_Up" [ (flag "move-workspace-up") ])
        (plain "Mod+Shift+U" [ (flag "move-workspace-down") ])
        (plain "Mod+Shift+I" [ (flag "move-workspace-up") ])

        # You can refer to workspaces by index. However, keep in mind that
        # niri is a dynamic workspace system, so these commands are kind of
        # "best effort". Trying to refer to a workspace index bigger than
        # the current workspace count will instead refer to the bottommost
        # (empty) workspace.
        (plain "Mod+1" [ (leaf "focus-workspace" "1terminal") ])
        (plain "Mod+2" [ (leaf "focus-workspace" "2browser") ])
        (plain "Mod+3" [ (leaf "focus-workspace" "3chat") ])
        (plain "Mod+4" [ (leaf "focus-workspace" "4music") ])
        (plain "Mod+5" [ (leaf "focus-workspace" "5mail") ])
        (plain "Mod+6" [ (leaf "focus-workspace" "6file") ])
        (plain "Mod+7" [ (leaf "focus-workspace" 7) ])
        (plain "Mod+8" [ (leaf "focus-workspace" 8) ])
        (plain "Mod+9" [ (leaf "focus-workspace" 9) ])
        (plain "Mod+0" [ (leaf "focus-workspace" "0other") ])
        (plain "Mod+Ctrl+1" [ (leaf "move-column-to-workspace" "1terminal") ])
        (plain "Mod+Ctrl+2" [ (leaf "move-column-to-workspace" "2browser") ])
        (plain "Mod+Ctrl+3" [ (leaf "move-column-to-workspace" "3chat") ])
        (plain "Mod+Ctrl+4" [ (leaf "move-column-to-workspace" "4music") ])
        (plain "Mod+Ctrl+5" [ (leaf "move-column-to-workspace" "5mail") ])
        (plain "Mod+Ctrl+6" [ (leaf "move-column-to-workspace" "6file") ])
        (plain "Mod+Ctrl+7" [ (leaf "move-column-to-workspace" 7) ])
        (plain "Mod+Ctrl+8" [ (leaf "move-column-to-workspace" 8) ])
        (plain "Mod+Ctrl+9" [ (leaf "move-column-to-workspace" 9) ])
        (plain "Mod+Ctrl+0" [ (leaf "move-column-to-workspace" "0other") ])

        (plain "Mod+Comma" [ (flag "consume-window-into-column") ])
        (plain "Mod+Period" [ (flag "expel-window-from-column") ])

        (plain "Mod+R" [ (flag "switch-preset-column-width") ])
        (plain "Mod+F" [ (flag "maximize-column") ])
        (plain "Mod+Shift+F" [ (flag "fullscreen-window") ])
        (plain "Mod+C" [ (flag "center-column") ])

        (plain "Mod+Minus" [ (leaf "set-column-width" "-10%") ])
        (plain "Mod+Equal" [ (leaf "set-column-width" "+10%") ])

        (plain "Mod+Shift+Minus" [ (leaf "set-window-height" "-10%") ])
        (plain "Mod+Shift+Equal" [ (leaf "set-window-height" "+10%") ])

        (plain "Print" [ (flag "screenshot") ])
        (plain "Ctrl+Print" [ (flag "screenshot-screen") ])
        (plain "Alt+Print" [ (flag "screenshot-window") ])

        (plain "Mod+Shift+E" [ (leaf "spawn" [ "wlogout" ]) ])

        (plain "Mod+Shift+P" [ (flag "power-off-monitors") ])

      ])
    ];
}
