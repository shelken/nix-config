{ myvars, ... }:
let
  dataDir = "/data/docker/dhp/data";
in
#############################################################
#
#  dhp：Docker Hub 的拉取代理（distribution registry 的 pull-through 缓存）
#
#  继续用容器：pull-through 本身 nixpkgs 的 services.dockerRegistry 能表达，
#  但换成原生后它监听宿主地址，不再是 homelab 网络里的容器名 dhp，
#  Caddyfile 里 `import service_docker dhp dhp 5000 robots_ban` 这行要改成宿主地址；
#  而这份 Caddyfile 与集群侧 caddy-external 的副本是要成对维护的双源，
#  另外 module 的存储目录默认在 /var/lib/docker-registry，与现有 /data/docker/dhp/data 不同。
#
#############################################################
{
  systemd.tmpfiles.rules = [
    "d ${dataDir} 0755 root root -"
  ];

  virtualisation.oci-containers.containers.dhp = {
    image = "registry:3.1@sha256:d4032d4cc323c1731c707931ecada07a53076eac38e3b61ae57533f170f2c6c3";
    autoStart = true;
    environment.REGISTRY_PROXY_REMOTEURL = "https://registry-1.docker.io";
    volumes = [
      "${dataDir}:/var/lib/registry"
      "${./mirror-config.yaml}:/etc/distribution/config.yml:ro"
      "/etc/localtime:/etc/localtime:ro"
    ];
    networks = [ "homelab" ];
    labels = {
      "homepage.group" = "VPS";
      "homepage.name" = "dhp";
      "homepage.icon" = "docker-moby.svg";
      "homepage.description" = "docker镜像registry";
    };
  };
}
