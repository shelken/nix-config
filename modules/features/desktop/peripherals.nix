{ config, ... }:
{
  flake.modules.nixos.gui.imports = [ config.flake.modules.nixos.peripherals ];

  flake.modules.nixos.peripherals =
    { pkgs, ... }:
    {
      security.rtkit.enable = true;
      services.pipewire = {
        enable = true;
        alsa.enable = true;
        alsa.support32Bit = true;
        pulse.enable = true;
      };

      hardware.bluetooth.enable = true;
      services.blueman.enable = true;

      services = {
        printing.enable = true;
        geoclue2.enable = true;

        udev.packages = with pkgs; [
          gnome-settings-daemon
        ];

        keyd = {
          enable = true;
          keyboards.default.settings.main = {
          };
        };
      };
    };
}
