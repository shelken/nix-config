{ pkgs, ... }:
{
  imports = [
    ./node-exporter.nix
    ./openlist.nix
    ./kopia.nix
  ];

  # 声明式确保 homelab 共享 bridge 网络存在且配置正确
  # 部署或系统开机时自动执行，容器 unit 依赖此服务
  systemd.services.docker-network-homelab = {
    description = "Docker network homelab (declarative bridge)";
    after = [ "docker.service" ];
    requires = [ "docker.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      if ! ${pkgs.docker}/bin/docker network inspect homelab >/dev/null 2>&1; then
        ${pkgs.docker}/bin/docker network create homelab \
          --driver bridge \
          --ipv6 \
          --subnet 172.20.0.0/16 \
          --gateway 172.20.0.1 \
          --subnet fd01:3d76:3407:1::/64 \
          --gateway fd01:3d76:3407:1::1 \
          --opt com.docker.network.driver.mtu=1280
      fi
    '';
  };
}
