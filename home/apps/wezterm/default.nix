{...}: {
  programs.wezterm = {
    # 使用Homebrew
    enable = false;
  };
  xdg.configFile = {
    "wezterm/wezterm.lua" = {
      source = ./wezterm.lua;
    };
  };
}
