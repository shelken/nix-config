{ config, ... }:
{
  sops.secrets."sbtools/server-private-key" = { };

  sops.templates."sbtools-server.env" = {
    content = ''
      SERVER_PRIVATE_KEY=${config.sops.placeholder."sbtools/server-private-key"}
    '';
    restartUnits = [ "docker-sbtools-server.service" ];
  };

  virtualisation.oci-containers.containers.sbtools-server = {
    image = "ghcr.io/shelken/proxy/sbtools-server:v0.8.5@sha256:946ef4fed6514232e7247ca126987428f9c0a1a6c35dfdccd53afc981208f9f6";
    autoStart = true;
    environment = {
      TZ = "Asia/Shanghai";
      PORT = "8080";
    };
    environmentFiles = [ config.sops.templates."sbtools-server.env".path ];
    networks = [ "homelab" ];
    extraOptions = [
      "--cap-drop=ALL"
      "--security-opt=no-new-privileges:true"
    ];
    labels = {
      "homepage.group" = "VPS";
      "homepage.name" = "sbtools";
      "homepage.icon" = "docker-moby.svg";
      "homepage.description" = "singbox配置生成服务";
    };
  };
}
