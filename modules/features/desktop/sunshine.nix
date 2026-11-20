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
        settings = {
          # pc  - Only localhost may access the web ui
          origin_web_ui_allowed = "pc";
          # 2   -	encryption is mandatory and unencrypted connections are rejected
          lan_encryption_mode = 2;
          wan_encryption_mode = 2;
        };
      };
    };
}
