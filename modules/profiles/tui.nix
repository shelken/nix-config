# tui：core + 终端开发环境，适合无桌面的远程开发机
# 只写角色链；gh、direnv、neovim、herdr、tui-cli 等由各自功能文件声明加入
{ config, ... }:
let
  inherit (config.flake.modules) darwin nixos;
in
{
  flake.modules.darwin.tui.imports = [ darwin.core ];
  flake.modules.nixos.tui.imports = [ nixos.core ];
  flake.modules.homeManager.tui = { };
}
