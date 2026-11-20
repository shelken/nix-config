{ config, ... }:
{
  flake.modules.nixos.gui.imports = [ config.flake.modules.nixos.qemu ];

  flake.modules.nixos.qemu =
    { pkgs, ... }:
    {
      boot.kernelModules = [ "vfio-pci" ];

      environment.systemPackages = with pkgs; [
        qemu_kvm

        qemu
      ];
    };
}
