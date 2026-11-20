{ config, ... }:
{
  sops.secrets."main-domain" = { };

  sops.templates."derp.env" = {
    content = ''
      DERP_DOMAIN=derp.${config.sops.placeholder."main-domain"}
    '';
    restartUnits = [ "docker-derp.service" ];
  };

  virtualisation.oci-containers.containers.derp = {
    image = "fredliang/derper:v1.104.7@sha256:e6f5025ebf4c87f593bc40ee0caa37f889759bceb87d4d9a165a383973e7d236";
    autoStart = true;
    environment = {
      TZ = "Asia/Shanghai";
      DERP_ADDR = ":8666";
      DERP_STUN_PORT = "3478";
      DERP_VERIFY_CLIENTS = "false";
    };
    environmentFiles = [ config.sops.templates."derp.env".path ];
    volumes = [ "/var/run/tailscale/tailscaled.sock:/var/run/tailscale/tailscaled.sock" ];
    extraOptions = [ "--network=host" ];
    labels = {
      "homepage.group" = "VPS";
      "homepage.name" = "derp服务";
      "homepage.icon" = "tailscale.svg";
      "homepage.description" = "derp服务";
    };
  };
}
