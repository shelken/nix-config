{ ... }:
{
  # programs.ssh = {
  #   inherit (myvars.networking.ssh) extraConfig;
  # };
  shelken = {
    backup = {
      enable = true;
      backupPaths = [ ];
    };
    dev.ai.enable = true;
    secrets.enable = true;
    tools.hammerspoon.enable = false;
    tools.backup.enable = true;
    wm.aerospace.enable = true;
    wm.hyprspace.enable = true;
  };
}
