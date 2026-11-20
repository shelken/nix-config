# dnscontrol：用声明式配置管理 Cloudflare 上的 DNS 记录
#
# 整份 dnsconfig.js（域名、IP、全部记录）用 sops 加密后放在本目录，只有 API token 在 secrets 仓库；
# 本功能只负责安装 dnscontrol 与放置 token，日常操作走 just dns::<配方>，用法见 README.md
#
# 可选功能：要用的主机在 imports 里加 self.modules.darwin.dnscontrol（NixOS 主机同理）
{
  # dnscontrol：安装工具并通过 dnscontrol-cf 封装 Cloudflare token，操作入口在 just/dns.just
  flake.modules.homeManager.dnscontrol =
    {
      config,
      lib,
      mylib,
      pkgs,
      ...
    }:
    let
      dnscontrolCf = pkgs.writeShellApplication {
        name = "dnscontrol-cf";
        text = ''
          token_file=${lib.escapeShellArg config.sops.secrets.dnscontrol-cloudflare-api-token.path}
          if ! token=$(< "$token_file") || [[ -z $token ]]; then
            echo "读不到 sops 的 dnscontrol/cloudflare-api-token：$token_file（本机未启用 secrets，或还没激活过）" >&2
            exit 1
          fi
          export CLOUDFLARE_API_TOKEN=$token
          exec mise exec -- dnscontrol "$@"
        '';
      };
    in
    {
      config = lib.mkIf config.shelken.secrets.enable {
        sops.secrets.dnscontrol-cloudflare-api-token = mylib.mkDefaultSecret {
          key = "dnscontrol/cloudflare-api-token";
        };

        home.packages = [ dnscontrolCf ];

        # 用 mise 而不是 nixpkgs：nixpkgs 的 dnscontrol 落后一个大版本（4.x）
        # renovate: datasource=github-releases depName=DNSControl/dnscontrol
        programs.mise.globalConfig.tools."github:DNSControl/dnscontrol" = "5.8.2";
      };
    };
}
