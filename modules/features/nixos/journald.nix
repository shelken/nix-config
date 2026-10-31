# journald：本地日志上限
# 服务器的登录日志已由主机自己的采集链路收走，本地只留近期的 → nixos.server
{ config, ... }:
{
  flake.modules.nixos.server.imports = [ config.flake.modules.nixos.journald ];

  flake.modules.nixos.journald = {
    services.journald.settings.Journal.SystemMaxUse = "200M";
  };
}
