{ ... }:
{
  flake.modules.nixos.vps-container-network =
    { config, pkgs, ... }:
    let
      network = pkgs.writeShellApplication {
        name = "vps-container-network";
        runtimeInputs = [
          pkgs.docker
          pkgs.jq
        ];
        text = builtins.readFile ./_network.sh;
      };
    in
    {
      virtualisation.docker = {
        enable = true;
        enableOnBoot = true;
      };
      sops.secrets."vps-containers/network" = { };
      system.build.vps-container-network = network;
      systemd.services.vps-container-network = {
        description = "核对或创建 VPS 容器共享网络";
        requires = [ "docker.service" ];
        after = [ "docker.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          TimeoutStartSec = 60;
          ExecStart = "${network}/bin/vps-container-network --ensure ${
            config.sops.secrets."vps-containers/network".path
          }";
        };
      };
    };
}
