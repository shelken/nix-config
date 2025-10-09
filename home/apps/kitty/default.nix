{
  myvars,
  pkgs,
  ...
}:
let
  kitty-icon-pkgs = pkgs.fetchFromGitHub {
    owner = "DinkDonk";
    repo = "kitty-icon";
    rev = "0bdece53";
    hash = "sha256-TLltUcfJpY+3rwvHYgtN4zBpbBnLBYyzDu90UMnxwoc=";
  };
in
{
  programs.kitty = {
    enable = true; # 用 homebrew 安装

    font = {
      name = "JetBrainsMono Nerd Font Mono";
      size = 18;
    };

    shellIntegration = {
      mode = "no-rc no-cursor";
      enableZshIntegration = true;
      enableBashIntegration = true;
    };

    keybindings = {
      "cmd+ctrl+," = "load_config_file";

      "cmd+t" = "new_tab";
      "cmd+w" = "close_tab";

      "cmd+shift+m" = "toggle_maximized";
      "cmd+shift+f" = "show_scrollback";

      "cmd+[" = "previous_tab";
      "cmd+]" = "next_tab";

      "cmd+c" = "copy_to_clipboard";
      "cmd+v" = "paste_from_clipboard";
      "cmd+shift+v" = "paste_from_selection";

      "cmd+enter" = "launch --cwd=current";

      "cmd+ctrl+up" = "move_window up";
      "cmd+ctrl+left" = "move_window left";
      "cmd+ctrl+right" = "move_window right";
      "cmd+ctrl+down" = "move_window down";

      "alt+shift+left" = "resize_window narrower 2";
      "alt+shift+right" = "resize_window wider 2";
      "alt+shift+up" = "resize_window taller 2";
      "alt+shift+down" = "resize_window shorter 2";
    };

    settings = {
      cursor_trail = 3;
      macos_show_window_title_in = "none";

      background_opacity = 0.88;
      background_blur = 64;

      hide_window_decorations = "titlebar-only";
      window_padding_width = "3 5 1 5";

      tab_bar_edge = "bottom";
      tab_bar_style = "powerline";
      tab_powerline_style = "slanted";
      tab_bar_min_tabs = 2;
      tab_title_template = "{title}{' :{}:'.format(num_windows) if num_windows > 1 else ''}";

      macos_option_as_alt = "yes";
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

  # xdg.configFile."kitty/kitty.conf" = {
  #   text = concatStrings [
  #     ''
  #       # Shell integration
  #       shell_integration ${shell_integration}
  #     ''
  #     origin_file
  #   ];
  # };
  # xdg.configFile."kitty/current-theme.conf" = {
  #   source = "${pkgs.kitty-themes}/share/kitty-themes/themes/${theme}";
  # };
  xdg.configFile."kitty/kitty.app.png" = {
    source = "${kitty-icon-pkgs}/kitty-light.png";
    # source = "${pkgs.kitty-icon}/kitty-light.png";
  };

  home.sessionVariables = {
    # TERM = "xterm-256color";
  };
}
