# 可选功能，需要时主机 imports = [ self.modules.nixos.nvidia ]
{
  flake.modules.nixos.nvidia =
    { config, ... }:
    {
      hardware.graphics = {
        enable = true;
        enable32Bit = true;
      };

      services.xserver.videoDrivers = [ "nvidia" ];

      hardware.nvidia = {
        modesetting.enable = true;

        powerManagement.enable = false;

        powerManagement.finegrained = false;

        open = false;

        nvidiaSettings = true;

        package = config.boot.kernelPackages.nvidiaPackages.stable;
      };
    };
}
