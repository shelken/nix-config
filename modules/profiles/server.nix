# server：core + 常驻服务器职责，适合公网 VPS，仅 NixOS
# 与 tui 并列，各自包含 core；不含开发工具链。只写角色链，journald、zram 等由各自功能文件声明加入。
# 主机特有的（端口、网络、sysctl）写在 hosts/ 里
{ config, ... }:
let
  inherit (config.flake.modules) nixos;
in
{
  flake.modules.nixos.server.imports = [ nixos.core ];
}
