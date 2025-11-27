{ ... }:
{
  # programs.ssh = {
  #   inherit (myvars.networking.ssh) extraConfig;
  # };
  shelken = {
    dev.ai.enable = false;
    secrets.enable = true;
    tools.hammerspoon.enable = false;
    tools.backup.enable = false;
    wm.aerospace.enable = true;
  };
}
