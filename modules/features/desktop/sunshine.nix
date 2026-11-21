{ config, ... }:
{
  flake.modules.nixos.gui.imports = [ config.flake.modules.nixos.sunshine ];

  flake.modules.nixos.sunshine =
    { lib, pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        moonlight-qt
      ];

      services.sunshine = {
        enable = lib.mkDefault false;
        autoStart = true;
        capSysAdmin = true;
        openFirewall = true;
        settings =
          let
            mandatoryEncryption = 2;
          in
          {
            origin_web_ui_allowed = "pc";
            lan_encryption_mode = mandatoryEncryption;
            wan_encryption_mode = mandatoryEncryption;
          };
      };
    };
}
