{ mylib, ... }:
{
  imports = (mylib.scanPaths ./.) ++ [
    ../base/core
    ../base/tui
    ../base/gui
    ../base/home.nix
  ];

  xdg.enable = true;
}
