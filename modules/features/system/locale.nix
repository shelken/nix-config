# 时区、区域与对时：北京时间、英文界面、中文区域格式、国内 NTP
# 所有 NixOS 主机的默认值 → nixos.core；位于国外的主机在自己的配置里覆盖
{ config, ... }:
{
  flake.modules.nixos.core.imports = [ config.flake.modules.nixos.locale ];

  flake.modules.nixos.locale = {
    time.timeZone = "Asia/Shanghai";
    networking.timeServers = [
      "ntp.aliyun.com"
      "ntp.tencent.com"
    ];

    # Select internationalisation properties.
    i18n.defaultLocale = "en_US.UTF-8";

    i18n.extraLocaleSettings = {
      LC_ADDRESS = "zh_CN.UTF-8";
      LC_IDENTIFICATION = "zh_CN.UTF-8";
      LC_MEASUREMENT = "zh_CN.UTF-8";
      LC_MONETARY = "zh_CN.UTF-8";
      LC_NAME = "zh_CN.UTF-8";
      LC_NUMERIC = "zh_CN.UTF-8";
      LC_PAPER = "zh_CN.UTF-8";
      LC_TELEPHONE = "zh_CN.UTF-8";
      LC_TIME = "zh_CN.UTF-8";
    };
  };
}
