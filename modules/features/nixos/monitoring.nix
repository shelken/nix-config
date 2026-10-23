# 监控：node_exporter 暴露在 9100 端口，供 homelab 采集
# 所有 NixOS 主机都需要 → nixos.core
{ config, ... }:
{
  flake.modules.nixos.core.imports = [ config.flake.modules.nixos.monitoring ];

  flake.modules.nixos.monitoring = {
    # enable the node exporter on all nixos hosts
    # https://github.com/NixOS/nixpkgs/blob/nixos-24.05/nixos/modules/services/monitoring/prometheus/exporters/node.nix
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
