# dnscontrol：配置目录软链 + dnscontrol-ctl 包装脚本；逻辑在 dnscontrol-ctl.sh
{
  config,
  lib,
  mylib,
  pkgs,
  ...
}:
let
  secretPath = name: config.sops.secrets.${name}.path;

  script = pkgs.writeShellApplication {
    name = "dnscontrol-ctl";
    runtimeInputs = [ pkgs.coreutils ];
    runtimeEnv = {
      CONFIG_DIR = "${config.xdg.configHome}/dnscontrol";
      DOMAIN_FILE = secretPath "dnscontrol-domain";
      VPS_V4_FILE = secretPath "dnscontrol-vps-ipv4";
      VPS_V6_FILE = secretPath "dnscontrol-vps-ipv6";
      VPS_V6_SECONDARY_FILE = secretPath "dnscontrol-vps-ipv6-secondary";
      CF_DCV_ID_FILE = secretPath "dnscontrol-cf-dcv-id";
      CLOUDFLARE_API_TOKEN_FILE = secretPath "dnscontrol-cloudflare-api-token";
    };
    text = builtins.readFile ./dnscontrol-ctl.sh;
  };
in
{
  config = lib.mkIf config.shelken.secrets.enable {
    sops.secrets = {
      dnscontrol-domain = mylib.mkDefaultSecret { key = "main-domain"; };
      dnscontrol-vps-ipv4 = mylib.mkDefaultSecret { key = "dnscontrol/vps-ipv4"; };
      dnscontrol-vps-ipv6 = mylib.mkDefaultSecret { key = "dnscontrol/vps-ipv6"; };
      dnscontrol-vps-ipv6-secondary = mylib.mkDefaultSecret { key = "dnscontrol/vps-ipv6-secondary"; };
      dnscontrol-cf-dcv-id = mylib.mkDefaultSecret { key = "dnscontrol/cf-dcv-id"; };
      dnscontrol-cloudflare-api-token = mylib.mkDefaultSecret {
        key = "dnscontrol/cloudflare-api-token";
      };
    };

    # 用 mise 而不是 nixpkgs：nixpkgs 的 dnscontrol 落后一个大版本（4.x）
    programs.mise.globalConfig.tools."github:DNSControl/dnscontrol" = "5.2.0";

    xdg.configFile."dnscontrol" = mylib.mkConfigFile config ./config;

    home.packages = [ script ];
  };
}
