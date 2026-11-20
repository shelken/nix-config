{ config, ... }:
{
  flake.modules.nixos.tui.imports = [ config.flake.modules.nixos.node-exporter ];

  flake.modules.nixos.node-exporter = {
    services.prometheus.exporters.node = {
      enable = true;
      listenAddress = "0.0.0.0";
      port = 9100;
      # There're already a lot of collectors enabled by default
      # https://github.com/prometheus/node_exporter?tab=readme-ov-file#enabled-by-default
      enabledCollectors = [
        "systemd"
        "logind"
      ];
    };
  };
}
