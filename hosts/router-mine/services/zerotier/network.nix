{
  uci.settings.network.zt = {
    _type = "interface";
    device = "{{ sops.zerotier.device }}";
    proto = "none";
  };
}
