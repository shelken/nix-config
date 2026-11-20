{ myvars, ... }:
let
  address = myvars.networking.hostAddress."vps-cc-ts".address;
in
{
  virtualisation.oci-containers.containers.node-exporter = {
    image = "prom/node-exporter:v1.13.1@sha256:7296504d4ada44b7d7ab4431e27e9f9900d8488f8d55842f4b12ae2704e16dfe";
    autoStart = true;
    cmd = [
      "--path.rootfs=/host/root"
      "--path.procfs=/host/proc"
      "--path.sysfs=/host/sys"
      "--path.udev.data=/host/root/run/udev/data"
      "--web.listen-address=0.0.0.0:9100"
      "--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($|/)"
    ];
    networks = [ "homelab" ];
    ports = [ "${address}:9100:9100/tcp" ];
    volumes = [
      "/:/host/root:ro"
      "/proc:/host/proc:ro"
      "/sys:/host/sys:ro"
    ];
    labels = {
      "homepage.group" = "VPS";
      "homepage.name" = "node-exporter";
      "homepage.icon" = "docker-moby.svg";
      "homepage.description" = "";
    };
  };
}
