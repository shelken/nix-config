{ ... }:
{
  virtualisation.oci-containers.containers.node-exporter = {
    image = "prom/node-exporter:v1.12.1@sha256:7164ff58d2aa236f06f5cd9a77efb32e6097ee8959f2a4eb9231f24d55734e94";
    autoStart = true;
    cmd = [
      "--path.rootfs=/host/root"
      "--path.procfs=/host/proc"
      "--path.sysfs=/host/sys"
      "--path.udev.data=/host/root/run/udev/data"
      "--web.listen-address=0.0.0.0:9100"
      "--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($|/)"
    ];
    ports = [ "9100:9100/tcp" ];
    volumes = [
      "/:/host/root:ro"
      "/proc:/host/proc:ro"
      "/sys:/host/sys:ro"
    ];
    extraOptions = [
      "--network=homelab"
      "--restart=always"
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
