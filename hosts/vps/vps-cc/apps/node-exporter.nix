{ myvars, ... }:
let
  address = myvars.networking.hostAddress."vps-cc-ts".address;
in
{
  virtualisation.oci-containers.containers.node-exporter = {
    image = "prom/node-exporter:v1.12.1@sha256:1b4e4438faca4dd7e001dd445d161a4a2091b0fededa84093b3a8dfeae1f1be0";
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

  systemd.services.docker-node-exporter = {
    after = [ "docker-network-homelab.service" ];
    requires = [ "docker-network-homelab.service" ];
  };
}
