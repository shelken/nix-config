{ myvars, pkgs, ... }:
{
  programs.wezterm = {
    # 使用Homebrew
    enable = false;
  };
  xdg.configFile = {
    "wezterm/wezterm.lua" = {
      source = pkgs.replaceVars ./wezterm.lua {
        inherit (myvars.fontFamilies) cjkMonospace monospace;
        themeName = myvars.catppuccin.displayName;
      };
    };
  };
}
