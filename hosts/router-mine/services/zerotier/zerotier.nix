# 节点身份与网络 ID 取自 1Password（router-mine 条目的 zerotier 分组）
{
  uci.packages = [ "luci-app-zerotier" ];

  uci.settings.zerotier = {
    global = {
      _type = "zerotier";
      enabled = "0";
      secret = "{{ op://Personal/router-mine/zerotier/secret }}";
    };
    main = {
      _type = "network";
      id = "{{ op://Personal/router-mine/zerotier/network-id }}";
      allow_default = "1";
      allow_global = "1";
    };
  };
}
