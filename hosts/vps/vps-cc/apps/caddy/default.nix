{ config, myvars, ... }:
let
  address = myvars.networking.hostAddress."vps-cc-ts".address;
  dataDir = "/data/docker/caddy";
  logDir = "/var/log/caddy";
in
#############################################################
#
#  caddy：公网入口（80/443），终止 TLS、反代集群与 VPS 上的服务
#
#  继续用镜像：镜像里带 Cloudflare DNS 插件与 CrowdSec AppSec 模块。
#  nixpkgs 的 services.caddy 配 pkgs.caddy.withPlugins 可以编插件，
#  但插件是 FOD、没有二进制缓存，每次插件集变化都要本地联网编一遍，
#  且镜像里有三个 @main 版插件，module 的 installCheck 比对版本会失败。
#  Caddyfile 用 {$VAR} 从环境取变量，所以机密走 sops 模板 + environmentFiles。
#
#############################################################
{
  systemd.tmpfiles.rules = [
    "d ${dataDir} 0755 root root -"
    "d ${dataDir}/site 0755 root root -"
    "d ${dataDir}/data 0755 root root -"
    "d ${dataDir}/config 0755 root root -"
    "d ${logDir} 0755 root root -"
  ];

  sops.secrets = {
    "main-domain" = { };
    "envoy-external-ip" = { };
    "caddy/cloudflare-api-token" = { };
    "crowdsec/lapi-url" = { };
    "crowdsec/caddy-bouncer-api-key" = { };
  };

  sops.templates."caddy.env" = {
    content = ''
      MAIN_DOMAIN=${config.sops.placeholder."main-domain"}
      ENVOY_EXTERNAL_IP=${config.sops.placeholder."envoy-external-ip"}
      CLOUDFLARE_API_TOKEN=${config.sops.placeholder."caddy/cloudflare-api-token"}
      CROWDSEC_LOCAL_API_URL=${config.sops.placeholder."crowdsec/lapi-url"}
      CROWDSEC_CADDY_BOUNCER_API_KEY=${config.sops.placeholder."crowdsec/caddy-bouncer-api-key"}
    '';
    restartUnits = [ "docker-caddy.service" ];
  };

  virtualisation.oci-containers.containers.caddy = {
    image = "ghcr.io/shelken/caddy:2.11.7@sha256:2866343d741867d6b40f59f0ca0103ec964ef394fc709167ce031048836789e9";
    autoStart = true;
    environment = {
      TZ = "Asia/Shanghai";
      # 与本机 sysctl 一起关掉 MPTCP：双入口场景下 MPTCP 会踩到内核缺陷
      GODEBUG = "multipathtcp=0";
    };
    environmentFiles = [ config.sops.templates."caddy.env".path ];
    volumes = [
      "${./Caddyfile}:/etc/caddy/Caddyfile:ro"
      "${dataDir}/site:/srv"
      "${dataDir}/data:/data"
      "${dataDir}/config:/config"
      "${logDir}:/var/log/caddy"
    ];
    # 80/443 是公网入口，按旧 Compose 发布到所有地址；
    # 2019 只是给 tailnet 侧的只读门面（/metrics、/reverse_proxy/upstreams），
    # 管理面本身在容器内的 unix socket，见 Caddyfile
    ports = [
      "80:80/tcp"
      "443:443/tcp"
      "443:443/udp"
      "${address}:2019:2019/tcp"
    ];
    extraOptions = [
      "--ulimit=nofile=65536:65536"
      "--sysctl=net.mptcp.enabled=0"
    ];
    networks = [ "homelab" ];
    # AppSec 后端在 crowdsec-agent 上：只保证启动顺序，连不上时 Caddy 自己重试
    dependsOn = [ "crowdsec-agent" ];
    labels = {
      "homepage.group" = "VPS";
      "homepage.name" = "vps-caddy";
      "homepage.icon" = "caddy.svg";
      "homepage.description" = "vps反向代理";
      "homepage.widget.type" = "caddy";
      "homepage.widget.url" = "http://ts-node-vps.network.svc:2019";
    };
  };
}
