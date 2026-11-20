{ config, ... }:
{
  flake.modules.nixos.gui.imports = [ config.flake.modules.nixos.desktop-security ];

  flake.modules.nixos.desktop-security =
    { pkgs, ... }:
    {
      security.polkit.enable = true;
      services.gnome = {
        gnome-keyring.enable = true;
        gcr-ssh-agent.enable = false;
      };
      programs.seahorse.enable = true;
      programs.ssh.startAgent = true;
      security.pam.services.greetd.enableGnomeKeyring = true;

      programs.gnupg.agent = {
        enable = true;
        pinentryPackage = pkgs.pinentry-qt;
        enableSSHSupport = false;
        settings.default-cache-ttl = 4 * 60 * 60;
      };
    };
}
