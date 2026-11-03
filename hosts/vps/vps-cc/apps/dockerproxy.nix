{ myvars, ... }:
let
  address = myvars.networking.hostAddress."vps-cc-ts".address;
in
#############################################################
#
#  dockerproxy：只读的 docker socket 代理，给 tailnet 侧的 Gatus 与 Homepage 用
#
#  继续用镜像：它的价值就是把 socket 收窄成少量只读端点，
#  nixpkgs 没有对等实现。端口只绑 tailnet 地址。
#
#############################################################
{
  virtualisation.oci-containers.containers.dockerproxy = {
    image = "ghcr.io/tecnativa/docker-socket-proxy:v0.5.0@sha256:1f5038b54f06c3e18422902cf00ba21803d1c97805aae032e5e6673d532d3459";
    autoStart = true;
    environment = {
      CONTAINERS = "1";
      SERVICES = "1";
      TASKS = "1";
      POST = "0";
      VOLUMES = "0";
      IMAGES = "0";
      INFO = "0";
      NETWORKS = "0";
    };
    volumes = [ "/var/run/docker.sock:/var/run/docker.sock:ro" ];
    ports = [ "${address}:2575:2375/tcp" ];
    networks = [ "homelab" ];
    labels = {
      "homepage.group" = "VPS";
      "homepage.name" = "docker-proxy";
      "homepage.icon" = "docker-moby.svg";
      "homepage.description" = "";
    };
  };
}
