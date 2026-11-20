{ config, ... }:
{
  flake.modules.nixos.gui.imports = [ config.flake.modules.nixos.podman ];

  flake.modules.nixos.podman = {
    virtualisation = {
      docker.enable = false;
      podman = {
        enable = true;
        dockerCompat = true;
        defaultNetwork.settings.dns_enabled = true;
        autoPrune = {
          enable = true;
          dates = "weekly";
          flags = [ "--all" ];
        };
      };

      oci-containers.backend = "podman";

    };
  };
}
