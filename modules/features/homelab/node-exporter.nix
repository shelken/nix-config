{
  flake.modules.darwin.node-exporter =
    { config, myvars, ... }:
    {
      services.prometheus.exporters.node = {
        enable = true;
        listenAddress = myvars.networking.hostAddress.${config.networking.hostName}.address;
        port = 9100;
      };
    };
}
