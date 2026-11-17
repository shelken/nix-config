# dnscontrol：用声明式配置管理 Cloudflare 上的 DNS 记录
#
# 整份 dnsconfig.js（域名、IP、全部记录）用 sops 加密后放在本目录，只有 API token 在 secrets 仓库；
# 本功能只负责安装 dnscontrol 与放置 token，日常操作走 just dns::<配方>，用法见 README.md
#
# 可选功能：要用的主机在 imports 里加 self.modules.darwin.dnscontrol（NixOS 主机同理）
{
  # dnscontrol：安装工具并把 Cloudflare token 放到固定路径，操作入口在 just/dns.just
  flake.modules.homeManager.dnscontrol =
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
    };
}
