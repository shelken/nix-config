# 桌面安全：polkit、gnome-keyring、ssh-agent、gpg-agent
# NixOS 桌面机 → nixos.gui
{ config, ... }:
{
  flake.modules.nixos.gui.imports = [ config.flake.modules.nixos.desktop-security ];

  flake.modules.nixos.desktop-security =
    { pkgs, ... }:
    {
      # security with polkit
      security.polkit.enable = true;
      # security with gnome-kering
      services.gnome = {
        gnome-keyring.enable = true;
        # Use gnome keyring's SSH Agent
        # https://wiki.gnome.org/Projects/GnomeKeyring/Ssh
        gcr-ssh-agent.enable = false;
      };
      # seahorse is a GUI App for GNOME Keyring.
      programs.seahorse.enable = true;
      # The OpenSSH agent remembers private keys for you
      # so that you don’t have to type in passphrases every time you make an SSH connection.
      # Use `ssh-add` to add a key to the agent.
      programs.ssh.startAgent = true;
      security.pam.services.greetd.enableGnomeKeyring = true;

      # gpg agent with pinentry
      programs.gnupg.agent = {
        enable = true;
        pinentryPackage = pkgs.pinentry-qt;
        enableSSHSupport = false;
        settings.default-cache-ttl = 4 * 60 * 60; # 4 hours
      };
    };
}
