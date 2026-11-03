{ ... }:
{
  flake.modules.nixos.vps-sub-converter =
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
        name = "sub-converter";
      };
    in
    {
      assertions = [
        {
          assertion = config.systemd.services ? vps-container-network;
          message = "vps-sub-converter 需要主机同时导入 vps-container-network。";
        }
      ];
      sops.secrets = {
        "vps-containers/main-domain" = { };
        "vps-containers/subconverter-api-token" = { };
      };
      sops.templates = {
        "sub-converter.env" = {
          content = ''
            MANAGED_PREFIX=https://sub.${config.sops.placeholder."vps-containers/main-domain"}
            API_TOKEN=${config.sops.placeholder."vps-containers/subconverter-api-token"}
          '';
          restartUnits = [ "docker-sub-converter.service" ];
        };
        "sub-converter.labels" = {
          content = ''
            homepage.group=VPS
            homepage.name=sub-converter
            homepage.icon=si-cplusplus
            homepage.href=https://sub.${config.sops.placeholder."vps-containers/main-domain"}/version
            homepage.description=订阅转换服务
          '';
          restartUnits = [ "docker-sub-converter.service" ];
        };
      };
      virtualisation.oci-containers = {
        backend = "docker";
        containers.sub-converter = {
          image = "ghcr.io/shelken/subconverter:1.8.1@sha256:b1e88944e8ed0baf6e47c872e445a080efa443a9432e5bc7efbb7cbb41afce70";
          autoStart = true;
          networks = [ "homelab" ];
          environment = {
            TZ = "Asia/Shanghai";
            API_MODE = "false";
          };
          environmentFiles = [ config.sops.templates."sub-converter.env".path ];
          ports = [ "127.0.0.1:25500:25500" ];
          log-driver = "json-file";
          labels."io.shelken.nix-managed" = "true";
          extraOptions = [
            "--cap-drop=ALL"
            "--security-opt=no-new-privileges:true"
            "--label-file=${config.sops.templates."sub-converter.labels".path}"
          ];
        };
      };
      systemd.services.docker-sub-converter = {
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
