{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ./node-exporter.nix
    ./openlist.nix
    ./kopia
    ./dnsmasq.nix
    ./caddy
    ./crowdsec-agent
    ./crowdsec-firewall-bouncer
    ./dhp
    ./homepage-labels.nix
    ./fluent-bit
    ./mosdns.nix
    ./sbtools-server.nix
    ./derp.nix
    ./hysteria2
    ./anytls
  ];

  config = {
    # 模块的默认后端不是 docker——stateVersion ≥ 22.05 默认 podman，
    # 不写这行会生成 podman-* 单元，等于悄悄换了容器引擎
    virtualisation.oci-containers.backend = "docker";

    systemd.services = {
      # 参数与旧 Compose 声明一致：MTU 1280 与出口 tailscale0 对齐，避免容器按 1500
      # 冷启动踩 PMTU 黑洞。已存在就不动它，否则正在运行的容器会连同网络一起被换掉。
      docker-network-homelab = {
        description = "homelab bridge network for the VPS containers";
        after = [ "docker.service" ];
        requires = [ "docker.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          ${pkgs.docker}/bin/docker network inspect homelab >/dev/null 2>&1 && exit 0

          ${pkgs.docker}/bin/docker network create homelab \
            --driver bridge \
            --ipv6 \
            --opt com.docker.network.driver.mtu=1280 \
            --subnet 172.20.0.0/16 \
            --subnet fd01:3d76:3407:1::/64
        '';
      };
    }
    // lib.mapAttrs' (
      name: container:
      lib.nameValuePair "docker-${name}" (
        {
          serviceConfig = {
            # 模块在这条上给了 on-failure，覆盖它必须显式提优先级
            Restart = lib.mkForce "always";
            RestartSec = "10s";
          };
        }
        // lib.optionalAttrs (builtins.elem "homelab" container.networks) {
          after = [ "docker-network-homelab.service" ];
          requires = [ "docker-network-homelab.service" ];
        }
      )
    ) config.virtualisation.oci-containers.containers;
  };
}
