{
  uci.packages = [ "prometheus-node-exporter-lua" ];

  uci.settings.prometheus-node-exporter-lua.main = {
    _type = "prometheus-node-exporter-lua";
    listen_interface = "lan";
    listen_port = "9100";
  };
}
