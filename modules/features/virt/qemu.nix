# QEMU/KVM 与 vfio-pci 直通
# NixOS 桌面机 → nixos.gui
{ config, ... }:
{
  flake.modules.nixos.gui.imports = [ config.flake.modules.nixos.qemu ];

  flake.modules.nixos.qemu =
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
