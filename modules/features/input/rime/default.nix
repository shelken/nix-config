# 鼠须管（Squirrel）+ 雾凇拼音：cask 与 rime 配置；
# 输入法是 GUI 才有意义的东西，tui/core 主机不需要
{ config, ... }:
{
  flake.modules.darwin.gui.imports = [ config.flake.modules.darwin.rime ];

  flake.modules.homeManager.rime.imports = [ ./_module.nix ];
  flake.modules.darwin.rime.homebrew.casks = [ "squirrel-app" ];
}
