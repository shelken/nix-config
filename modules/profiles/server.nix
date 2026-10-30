# server：core + 常驻服务器职责，适合公网 VPS，仅 NixOS
# 与 tui 并列，各自包含 core；不含开发工具链。只写角色链，具体功能由各自的功能文件声明加入。
# 下面是所有服务器共有的默认值，主机特有的（端口、网络、sysctl）写在 hosts/ 里
{ config, ... }:
let
  inherit (config.flake.modules) nixos;
in
{
  flake.modules.nixos.server = {
    imports = [ nixos.core ];

    # 登录日志已由主机自己的采集链路收走，本地只留近期的
    services.journald.extraConfig = ''
      SystemMaxUse=200M
    '';

    # 小内存机器：内存里压缩的 swap，不占磁盘 I/O
    zramSwap.enable = true;
  };
}
