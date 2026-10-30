# 启动：systemd-boot 保留代数与控制台分辨率
# 所有 NixOS 主机都需要 → nixos.core；电源管理是笔记本/桌面的事，见 features/gui/power.nix
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
    };
}
