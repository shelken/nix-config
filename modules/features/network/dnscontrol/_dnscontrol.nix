# dnscontrol：解密 dnsconfig.js、链接 creds.json、生成 dnscontrol-ctl；逻辑在 dnscontrol-ctl.sh
{
  config,
  lib,
  mylib,
  pkgs,
  ...
}:
let
  configDir = "${config.xdg.configHome}/dnscontrol";

  script = pkgs.writeShellApplication {
    name = "dnscontrol-ctl";
    runtimeInputs = [ pkgs.coreutils ];
    runtimeEnv = {
      CONFIG_DIR = configDir;
      CLOUDFLARE_API_TOKEN_FILE = config.sops.secrets.dnscontrol-cloudflare-api-token.path;
    };
    text = builtins.readFile ./dnscontrol-ctl.sh;
  };
in
{
  config = lib.mkIf config.shelken.secrets.enable {
    sops.secrets = {
      # 整份配置加密进本仓库：公开仓库里只有密文，看不到记录表
      dnscontrol-config = {
        sopsFile = ./dnsconfig.js.enc;
        format = "binary";
        path = "${configDir}/dnsconfig.js";
        mode = "0400";
      };
      dnscontrol-cloudflare-api-token = mylib.mkDefaultSecret {
        key = "dnscontrol/cloudflare-api-token";
      };
    };

    # 用 mise 而不是 nixpkgs：nixpkgs 的 dnscontrol 落后一个大版本（4.x）
    programs.mise.globalConfig.tools."github:DNSControl/dnscontrol" = "5.2.0";

    # 只链接文件而不是整个目录：dnsconfig.js 由 sops-nix 写入同一目录
    xdg.configFile."dnscontrol/creds.json" = mylib.mkConfigFile config ./creds.json;

    home.packages = [ script ];
  };
}
