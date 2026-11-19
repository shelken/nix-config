# 节点身份与网络 ID 在 secrets.nix 的 sops（router-mine.yaml 的 zerotier）
# 平时关着，需要时在 LuCI 临时打开；下次 push 会把它关回去
{
  uci.packages = [ "luci-i18n-zerotier-zh-cn" ];

  uci.settings.zerotier = {
    global = {
      _type = "zerotier";
      enabled = "0";
      secret = "{{ sops.zerotier.secret }}";
    };
    main = {
      _type = "network";
      id = "{{ sops.zerotier.network-id }}";
      allow_default = "1";
      allow_global = "1";
    };
  };
}
