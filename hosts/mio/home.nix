{ config, ... }:
{
  # programs.ssh = {
  #   inherit (myvars.networking.ssh) extraConfig;
  # };
  shelken = {
    dotfiles.liveEdit = true;

    backup.backupPaths = [
      "${config.home.homeDirectory}/Code"
    ];

    dev.ai.sandbox.enable = true;
  };
}
