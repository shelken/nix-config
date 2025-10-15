{ ... }:
{
  # programs.ssh = {
  #   inherit (myvars.networking.ssh) extraConfig;
  # };
  shelken = {
    wm.aerospace.enable = true;

    dev.ai.enable = true;

    tools.hammerspoon.enable = false;
    secrets.enable = true;
  };
}
