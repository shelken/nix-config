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
#  手动步骤见 docs/user-guide/06-vps-containers.md
#
#############################################################
{
  imports = [
    ./node-exporter.nix
    ./openlist.nix
    ./kopia
  ];

  options.shelken.vpsContainers.tailscaleAddress = lib.mkOption {
    type = lib.types.str;
    example = "100.64.0.1";
    description = ''
      业务容器的端口只发布到这个地址（Tailscale 网卡）。
      Docker 发布端口走 NAT，绕过 NixOS 防火墙：发布到 0.0.0.0 等于直接放到公网，
      发布到 127.0.0.1 则 Tailscale 侧的调用方（Gatus、Prometheus）访问不到。
      地址由主机事实提供，公开仓库不写字面量。
    '';
  };

  config = {
    # 继续用 Docker：旧 Compose 的容器、卷、网络都在 Docker 上。
    # 模块的默认后端不是 docker——stateVersion ≥ 22.05 默认 podman，
    # 不写这行会生成 podman-* 单元，等于悄悄换了容器引擎
    virtualisation.oci-containers.backend = "docker";

    systemd.services = {
      # homelab：业务容器共用的 bridge 网络，容器之间用容器名互相解析
      # （kopia 连 openlist 的 WebDAV）。参数与旧 Compose 声明一致：
      # MTU 1280 与出口 tailscale0 对齐，避免容器按 1500 冷启动踩 PMTU 黑洞。
      # 已存在就不动它，否则正在运行的容器会连同网络一起被换掉。
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
    # 旧 Compose 用 restart: always：容器退出就拉起。
    # 容器交给 systemd 后，模块默认的 Restart=on-failure 会放走「退出码 0 退出」这种情况，
    # 这里统一改回 always；10s 间隔避免崩溃时把日志打满（docker 自己的退避由 systemd 承担）
    // lib.mapAttrs' (
      name: _:
      lib.nameValuePair "docker-${name}" {
        serviceConfig = {
          # 模块在这条上给了 on-failure，覆盖它必须显式提优先级
          Restart = lib.mkForce "always";
          RestartSec = "10s";
        };
      }
    ) config.virtualisation.oci-containers.containers;
  };
}
