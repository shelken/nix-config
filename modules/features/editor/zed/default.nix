# Zed 编辑器：cask 加入 desktop；HM 配置在 _hm.nix
{ config, ... }:
{
  flake.modules.darwin.desktop.imports = [ config.flake.modules.darwin.zed ];

  flake.modules.darwin.zed.homebrew.casks = [ "zed" ];

  flake.modules.homeManager.zed = import ./_hm.nix;
}
