{ myvars, ... }:
let
  dataDir = "/data/docker/dhp/data";
in
{
  systemd.tmpfiles.rules = [
    "d ${dataDir} 0755 root root -"
  ];

  virtualisation.oci-containers.containers.dhp = {
    image = "registry:3.1@sha256:82f6ff4a7f982960c8aa51617fea3aabc485df6e55cce80d22deb1de36f1bc3c";
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
