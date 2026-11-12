# dnscontrol：安装工具并把 Cloudflare token 放到固定路径，操作入口在 just/dns.just
{
  config,
  lib,
  mylib,
  ...
}:
{
  config = lib.mkIf config.shelken.secrets.enable {
    # 路径固定，just/dns.just 的 token_file 读取同一个位置
    sops.secrets.dnscontrol-cloudflare-api-token = mylib.mkDefaultSecret {
      key = "dnscontrol/cloudflare-api-token";
      path = "${config.xdg.configHome}/dnscontrol/cloudflare-api-token";
    };

    # 用 mise 而不是 nixpkgs：nixpkgs 的 dnscontrol 落后一个大版本（4.x）
    # renovate: datasource=github-releases depName=DNSControl/dnscontrol
    programs.mise.globalConfig.tools."github:DNSControl/dnscontrol" = "5.8.2";
  };
}
