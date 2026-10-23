# tui：core + 终端开发环境，适合无桌面的远程开发机
{ config, ... }:
let
  inherit (config.flake.modules) darwin nixos homeManager;
in
{
  flake.modules.darwin.tui.imports = [ darwin.core ];
  flake.modules.nixos.tui.imports = [ nixos.core ];

  flake.modules.homeManager.tui.imports = [
    homeManager.gh
    homeManager.direnv
    homeManager.tui-cli
    homeManager.neovim
    homeManager.herdr
  ];
}
