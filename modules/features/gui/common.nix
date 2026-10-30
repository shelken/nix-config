# 常用 GUI 桌面应用（公共 casks）
{ config, ... }:
{
  flake.modules.darwin.gui.imports = [ config.flake.modules.darwin.gui-common ];

  flake.modules.darwin.gui-common.homebrew.casks = [
    # input-source
    "squirrel-app"

    # browser
    "google-chrome"
    "helium-browser"

    # misc
    "stats"
    "appcleaner"
    "the-unarchiver"
    "parsec"

    # network
    "tailscale-app"
    "zerotier-one"

    # quicklook
    "qlmarkdown"
    "syntax-highlight"
  ];
}
