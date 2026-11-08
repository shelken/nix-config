{
  config,
  lib,
  pkgs,
  ...
}:
#############################################################
#
#  vps-cc 的业务容器：原先由 home-ops 的 docker compose 部署，
#  现在改由 NixOS 的 virtualisation.oci-containers 声明（Docker backend）。
#
#  一个容器一个文件；只有本机用到的容器放这里，不进 modules/features。
#  手动步骤见 docs/user-guide/06-containers.md
#
#############################################################
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
    # 继续用 Docker：旧 Compose 的容器、卷、网络都在 Docker 上。
    # 模块的默认后端不是 docker——stateVersion ≥ 22.05 默认 podman，
    # 不写这行会生成 podman-* 单元，等于悄悄换了容器引擎
    virtualisation.oci-containers.backend = "docker";

    systemd.services = {
      # homelab：业务容器共用的 bridge 网络，容器之间用容器名互相解析
      # （kopia 连 openlist 的 WebDAV、caddy 连 crowdsec-agent 的 AppSec）。
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
    # 两个每台容器都要有的约定，按容器属性自动生成，服务文件里不再重复：
    # 1) 旧 Compose 用 restart: always：容器退出就拉起。容器交给 systemd 后，
    #    模块默认的 Restart=on-failure 会放走「退出码 0 退出」这种情况，这里统一改回
    #    always；10s 间隔避免崩溃时把日志打满（docker 自己的退避由 systemd 承担）
    # 2) 用 homelab 网络的容器要等网络单元创建好网络。用 `--network=host` 的容器
    #    （derp、hysteria2、anytls、crowdsec 防火墙 bouncer）不在这个网络里，跳过
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
