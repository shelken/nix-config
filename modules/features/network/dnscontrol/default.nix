{
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
      config = lib.mkMerge [
        {
          assertions = [
            {
              assertion = config.shelken.secrets.enable;
              message = "dnscontrol: 需要主机启用 secrets (shelken.secrets.enable = true)";
            }
          ];
        }
        (lib.mkIf config.shelken.secrets.enable {
          sops.secrets.dnscontrol-cloudflare-api-token = mylib.mkDefaultSecret {
            key = "dnscontrol/cloudflare-api-token";
          };

          home.packages = [ dnscontrolCf ];

          # renovate: datasource=github-releases depName=DNSControl/dnscontrol
          programs.mise.globalConfig.tools."github:DNSControl/dnscontrol" = "5.10.1";
        })
      ];
    };
}
