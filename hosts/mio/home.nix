{ ... }:
{
  # programs.ssh = {
  #   inherit (myvars.networking.ssh) extraConfig;
  # };
  shelken = {
    wm.aerospace.enable = true;
    tools.hammerspoon.enable = true;
    secrets.enable = true;
  };
}
