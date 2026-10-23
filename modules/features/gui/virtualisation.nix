# 容器与虚拟化：podman（docker 兼容）、flatpak、oci-containers、qemu、vfio-pci
# NixOS 桌面机 → nixos.gui
{ config, ... }:
{
  flake.modules.nixos.gui.imports = [ config.flake.modules.nixos.desktop-virt ];

  flake.modules.nixos.desktop-virt =
    { lib, pkgs, ... }:
    {
      # Enable nested virtualization, required by security containers and nested vm.
      # This should be set per host in /hosts, not here.
      #
      ## For AMD CPU, add "kvm-amd" to kernelModules.
      # boot.kernelModules = ["kvm-amd"];
      # boot.extraModprobeConfig = "options kvm_amd nested=1";  # for amd cpu
      #
      ## For Intel CPU, add "kvm-intel" to kernelModules.
      # boot.extraModprobeConfig = "options kvm_intel nested=1"; # for intel cpu
      boot.kernelModules = [ "vfio-pci" ];

      services.flatpak.enable = true;

      virtualisation = {
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

      # mkOrder：保持迁移前 qemu 在 moonlight/fhs/桌面包之前（见 system-path 的 ignoreCollisions）
      environment.systemPackages = lib.mkOrder 610 (
        with pkgs;
        [
          # QEMU/KVM(HostCpuOnly), provides:
          #   qemu-storage-daemon qemu-edid qemu-ga
          #   qemu-pr-helper qemu-nbd elf2dmp qemu-img qemu-io
          #   qemu-kvm qemu-system-x86_64 qemu-system-aarch64 qemu-system-i386
          qemu_kvm

          # Install QEMU(other architectures), provides:
          #   qemu-loongarch64 qemu-system-loongarch64
          #   qemu-riscv64 qemu-system-riscv64 qemu-riscv32  qemu-system-riscv32
          #   qemu-system-arm qemu-arm qemu-armeb qemu-system-aarch64 qemu-aarch64 qemu-aarch64_be
          #   qemu-system-xtensa qemu-xtensa qemu-system-xtensaeb qemu-xtensaeb
          qemu
        ]
      );
    };
}
