{ config, ... }:
{
  flake.modules.nixos.tui.imports = [ config.flake.modules.nixos.node-exporter ];

  flake.modules.nixos.node-exporter = {
    services.prometheus.exporters.node = {
      enable = true;
      listenAddress = "0.0.0.0";
      port = 9100;
      enabledCollectors = [
        "systemd"
        "logind"
      ];
    };
  };
}
