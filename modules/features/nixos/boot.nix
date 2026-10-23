# 启动与电源管理：systemd-boot 保留代数、高分辨率控制台、power-profiles-daemon、upower
# 所有 NixOS 主机都需要 → nixos.core
{ config, ... }:
{
  flake.modules.nixos.core.imports = [ config.flake.modules.nixos.boot ];

  flake.modules.nixos.boot =
    { lib, ... }:
    {
      boot.loader.systemd-boot = {
        # we use Git for version control, so we don't need to keep too many generations.
        configurationLimit = lib.mkDefault 10;
        # pick the highest resolution for systemd-boot's console.
        consoleMode = lib.mkDefault "max";
      };

      # for power management
      services = {
        power-profiles-daemon.enable = true;
        upower.enable = true;
      };
    };
}
