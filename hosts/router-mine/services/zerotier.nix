# 节点身份 global.secret 与网络 ID main.id 在私有部分补进同名段；
# nuci 会删掉声明段里没写的选项，缺了私有部分不要下发
{
  uci.packages = [ "luci-app-zerotier" ];

  uci.settings.zerotier = {
    global = {
      _type = "zerotier";
      enabled = "0";
      fw_allow_input = "1";
    };
    main = {
      _type = "network";
      allow_default = "1";
      allow_global = "1";
      fw_allow_forward = "1";
      fw_allow_input = "1";
    };
  };
}
