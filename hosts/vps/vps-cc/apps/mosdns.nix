{ config, myvars, ... }:
let
  address = myvars.networking.hostAddress."vps-cc-ts".address;
in
#############################################################
#
#  mosdns：上游分流解析，Caddy 用它做 vdns 的明文 DNS 入口
#
#  配置烘在自建镜像里，只有上游 DNS 走环境变量，继续用镜像。
#  5054 仍发布到所有地址（与旧 Compose 一致）：tailnet 侧 Gatus 从
#  100.97.0.8:5054 探测，公网设备按原样用这个明文 DNS 入口。
#
#############################################################
{
  sops.secrets = {
    "mosdns/remote-dns-server-1" = { };
    "mosdns/remote-dns-server-2" = { };
  };

  sops.templates."mosdns.env" = {
    content = ''
      REMOTE_DNS_SERVER_1=${config.sops.placeholder."mosdns/remote-dns-server-1"}
      REMOTE_DNS_SERVER_2=${config.sops.placeholder."mosdns/remote-dns-server-2"}
    '';
    restartUnits = [ "docker-mosdns.service" ];
  };

  virtualisation.oci-containers.containers.mosdns = {
    image = "ghcr.io/shelken/mosdns:vps-latest@sha256:86e4406f88eccfd51c1183f6fffcbe3e85ac7359f6b63f9b8a53f5532161babb";
    autoStart = true;
    environment.TZ = "Asia/Shanghai";
    environmentFiles = [ config.sops.templates."mosdns.env".path ];
    ports = [
      "5054:53/tcp"
      "5054:53/udp"
    ];
    networks = [ "homelab" ];
    labels = {
      "homepage.group" = "VPS";
      "homepage.name" = "mosdns";
      "homepage.icon" = "azure-dns.svg";
      "homepage.description" = "dns服务";
    };
  };
}
