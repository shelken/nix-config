# wezterm：终端配置软链
# 可选功能，需要时主机 imports = [ self.modules.darwin.wezterm ]
# 或 nixos.wezterm（HM 部分随同名挂接）
{
  flake.modules.homeManager.wezterm =
    { myvars, pkgs, ... }:
    {
      programs.wezterm.enable = false;

      xdg.configFile."wezterm/wezterm.lua".source = pkgs.replaceVars ./wezterm.lua {
        inherit (myvars.fontFamilies) cjkMonospace monospace;
        themeName = myvars.catppuccin.displayName;
      };
    };
}
