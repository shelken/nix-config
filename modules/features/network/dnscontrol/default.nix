{
  flake.modules.homeManager.dnscontrol =
    {
      config,
      pkgs,
      ...
    }:
    let
      dnscontrolCf = pkgs.writeShellApplication {
        name = "dnscontrol-cf";
        runtimeInputs = [ pkgs._1password-cli ];
        text = ''
          if ! token=$(env -u OP_SERVICE_ACCOUNT_TOKEN op read "op://Projects/nix-config/cloudflare-dnscontrol-token") || [[ -z "$token" ]]; then
            echo "无法从 1Password 读取 op://Projects/nix-config/cloudflare-dnscontrol-token（请确认 1Password 桌面 App 已解锁且命令行集成已开启）" >&2
            exit 1
          fi
          export CLOUDFLARE_API_TOKEN="$token"
          exec mise exec -- dnscontrol "$@"
        '';
      };
    in
    {
      assertions = [
        {
          assertion = config.shelken.secrets.enable;
          message = "dnscontrol: 需要主机启用 secrets（sops 解密 dnsconfig.sops.js 依赖本机 age 密钥）";
        }
      ];

      home.packages = [ dnscontrolCf ];

      # renovate: datasource=github-releases depName=DNSControl/dnscontrol
      programs.mise.globalConfig.tools."github:DNSControl/dnscontrol" = "5.10.1";
    };
}
