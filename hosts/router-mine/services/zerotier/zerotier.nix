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
