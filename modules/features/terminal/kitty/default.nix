{ config, ... }:
{
  flake.modules.darwin.gui.imports = [ config.flake.modules.darwin.kitty ];
  flake.modules.nixos.gui.imports = [ config.flake.modules.nixos.kitty ];

  flake.modules.homeManager.kitty =
    {
      config,
      inputs,
      lib,
      myvars,
      ...
    }:
    let
      palette =
        (lib.importJSON "${config.catppuccin.sources.palette}/palette.json")
        .${myvars.catppuccin.flavor}.colors;
      hex = c: lib.removePrefix "#" c.hex;
      bar = hex palette.crust;
      pill = hex palette.mauve;
      dim = hex palette.overlay0;
    in
    {
      programs.kitty = {
        enable = true;

        darwinLaunchOptions = [
        ];

        font = {
          name = myvars.fontFamilies.monospace;
          size = 18;
        };

        shellIntegration = {
          mode = "no-rc no-cursor";
          enableZshIntegration = true;
          enableBashIntegration = true;
        };

        extraConfig = "";

        keybindings = {
          # pi：协议协商失败时 Shift+Enter 会退化成普通 Enter；强制发 CSI-u（#5188）
          "shift+enter" = "send_text all \\x1b[13;2u";

          "cmd+ctrl+," = "load_config_file";

          "cmd+t" = "new_tab";
          "cmd+w" = "close_tab";
          # 默认 ctrl+shift+q 会关 tab，与 pi dequeue 冲突；关 tab 用上面 cmd+w
          "ctrl+shift+q" = "no_op";

          "cmd+shift+m" = "toggle_maximized";
          "cmd+shift+l" = "next_layout";
          "cmd+shift+f" = "show_scrollback";

          "cmd+c" = "copy_to_clipboard";
          "cmd+v" = "paste_from_clipboard";
          "cmd+shift+v" = "paste_from_selection";

          "cmd+d" = "launch --location=vsplit --cwd=current";
          "cmd+shift+d" = "launch --location=hsplit --cwd=current";

          "cmd+[" = "previous_tab";
          "cmd+]" = "next_tab";

          "cmd+ctrl+up" = "move_window up";
          "cmd+ctrl+left" = "move_window left";
          "cmd+ctrl+right" = "move_window right";
          "cmd+ctrl+down" = "move_window down";

          "cmd+left" = "neighboring_window left";
          "cmd+right" = "neighboring_window right";
          "cmd+up" = "neighboring_window up";
          "cmd+down" = "neighboring_window down";

          "alt+shift+left" = "resize_window narrower 2";
          "alt+shift+right" = "resize_window wider 2";
          "alt+shift+up" = "resize_window taller 2";
          "alt+shift+down" = "resize_window shorter 2";
        };

        settings = {
          symbol_map = "U+2E80-U+9FFF,U+F900-U+FAFF,U+FE30-U+FE4F,U+FF00-U+FFEF,U+20000-U+3FFFF ${myvars.fontFamilies.cjkMonospace}";

          allow_remote_control = "socket-only";
          listen_on = "unix:/tmp/kitty-{kitty_pid}";
          cursor_trail = 3;
          macos_show_window_title_in = "none";

          background_opacity = 0.88;
          background_blur = 64;

          hide_window_decorations = "titlebar-only";
          window_padding_width = "3 5 1 5";

          tab_bar_edge = "bottom";
          tab_bar_style = "separator";
          tab_separator = ''""'';
          tab_bar_min_tabs = 2;
          # 以空格开头/结尾的值必须加引号，否则 kitty 解析时会去掉
          tab_title_template = ''"  {fmt.fg._${dim}}{index} {fmt.fg.tab}{title.rsplit('/', 1)[-1]}  "'';
          active_tab_title_template = "{fmt.fg._${pill}}{fmt.bg._${bar}}{fmt.bg.tab}{fmt.fg.tab} {index} {title.rsplit('/', 1)[-1]} {fmt.fg._${pill}}{fmt.bg._${bar}}";

          macos_option_as_alt = "yes";

          enabled_layouts = "splits,stack";
        };

        quickAccessTerminalConfig = {
          background_opacity = "0.65";
          edge = "center-sized";
          start_as_hidden = "no";
          hide_on_focus_loss = "yes";
          lines = "35";
          columns = "126";
        };

        environment = {
        };
      };

      xdg.configFile."kitty/kitty.app.png" = {
        source = "${inputs.kitty-icon}/kitty-light.png";
      };

      home.sessionVariables = {
      };
    };
}
