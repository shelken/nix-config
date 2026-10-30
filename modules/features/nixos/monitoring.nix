# 监控：node_exporter 暴露在 9100 端口，供 homelab 采集
# 局域网内的主机才用 → nixos.tui；公网服务器自行决定监听地址，不继承 0.0.0.0
{ config, ... }:
{
  flake.modules.nixos.tui.imports = [ config.flake.modules.nixos.monitoring ];

  flake.modules.nixos.monitoring = {
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
