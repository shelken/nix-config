# gui：tui + 桌面环境与图形应用
# 功能（niri、anyrun、fonts、kitty 等）由各自文件声明加入；
# 只适用 Linux 的 HM 功能同时声明 nixos.gui，不会挂到 darwin 角色上
{ config, ... }:
let
  inherit (config.flake.modules) darwin nixos;
in
{
  flake.modules.darwin.gui.imports = [ darwin.tui ];
  flake.modules.nixos.gui.imports = [ nixos.tui ];
}
