{ ... }:
{
  flake.modules.nixos.vps-sbtools-server =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      ownership = import ./_ownership.nix {
        docker = pkgs.docker;
        inherit lib;
        name = "sbtools-server";
      };
    in
    {
      assertions = [
        {
          assertion = config.systemd.services ? vps-container-network;
          message = "vps-sbtools-server 需要主机同时导入 vps-container-network。";
        }
      ];
      sops.secrets = {
        "vps-containers/main-domain" = { };
        "vps-containers/sbtools-private-key" = { };
      };
      sops.templates = {
        "sbtools-server.env" = {
          content = ''
            SERVER_PRIVATE_KEY=${config.sops.placeholder."vps-containers/sbtools-private-key"}
          '';
          restartUnits = [ "docker-sbtools-server.service" ];
        };
        "sbtools-server.labels" = {
          content = ''
            homepage.group=VPS
            homepage.name=sbtools-server
            homepage.icon=si-go
            homepage.href=https://subs.${config.sops.placeholder."vps-containers/main-domain"}
            homepage.description=订阅信息同步服务
          '';
          restartUnits = [ "docker-sbtools-server.service" ];
        };
      };
      virtualisation.oci-containers = {
        backend = "docker";
        containers.sbtools-server = {
          image = "ghcr.io/shelken/proxy/sbtools-server:v0.7.4@sha256:96ed6204f14a1f24b86e87d09f9252be16b43109a31a6996260d6dddfe77dba8";
          autoStart = true;
          networks = [ "homelab" ];
          cmd = [
            "--port"
            "8080"
          ];
          environment.TZ = "Asia/Shanghai";
          environmentFiles = [ config.sops.templates."sbtools-server.env".path ];
          log-driver = "json-file";
          labels."io.shelken.nix-managed" = "true";
          extraOptions = [
            "--cap-drop=ALL"
            "--security-opt=no-new-privileges:true"
            "--label-file=${config.sops.templates."sbtools-server.labels".path}"
          ];
        };
      };
      systemd.services.docker-sbtools-server = {
        requires = [ "vps-container-network.service" ];
        after = [ "vps-container-network.service" ];
        preStart = lib.mkBefore ownership.check;
        preStop = lib.mkForce ownership.stop;
        postStop = lib.mkForce ownership.remove;
        unitConfig.StartLimitIntervalSec = lib.mkForce 0;
        serviceConfig.Restart = lib.mkForce "always";
      };
    };
}
