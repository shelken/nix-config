{ mylib, ... }:
{
  imports = [
    ../base/core
    ../base/tui
    ../base/home.nix
  ]
  ++ (mylib.scanPaths ./.)
  ++ [
    # 特定应用
    ../apps/raycast
    ../apps/hammerspoon
    ../apps/karabiner
    ../apps/chromium
    ../apps/neovim
    ../apps/dev
    ../apps/wezterm
    ../apps/squirrel
    ../apps/kitty
    ../apps/screenshot
    ../apps/tailscale/base.nix
  ];
}
