# Podman：docker 兼容的容器运行时，也是 oci-containers 的后端
# NixOS 桌面机 → nixos.gui
{ config, ... }:
{
  flake.modules.nixos.gui.imports = [ config.flake.modules.nixos.podman ];

  flake.modules.nixos.podman = {
    virtualisation = {
      # 与 virt/docker.nix 互斥：桌面机用 podman 的 docker 兼容层
      docker.enable = false;
      podman = {
        enable = true;
        # Create a `docker` alias for podman, to use it as a drop-in replacement
        dockerCompat = true;
        # Required for containers under podman-compose to be able to talk to each other.
        defaultNetwork.settings.dns_enabled = true;
        # Periodically prune Podman resources
        autoPrune = {
          enable = true;
          dates = "weekly";
          flags = [ "--all" ];
        };
      };

      oci-containers.backend = "podman";

      # Usage: https://wiki.nixos.org/wiki/Waydroid
      # waydroid.enable = true;

      # libvirtd = {
      #   enable = true;
      #   # hanging this option to false may cause file permission issues for existing guests.
      #   # To fix these, manually change ownership of affected files in /var/lib/libvirt/qemu to qemu-libvirtd.
      #   qemu.runAsRoot = true;
      # };

      # lxd.enable = true;
    };
  };
}
