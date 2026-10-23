# 鼠须管（Squirrel）+ 雾凇拼音：rime 配置随 cask（gui-common 的 squirrel-app）进 gui；
# 输入法是 GUI 才有意义的东西，tui/core 主机不需要
{ config, ... }:
{
  flake.modules.darwin.gui.imports = [ config.flake.modules.darwin.rime ];

  flake.modules.homeManager.rime.imports = [ ./_module.nix ];
}
