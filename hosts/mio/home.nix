{...}: {
  # programs.ssh = {
  #   inherit (myvars.networking.ssh) extraConfig;
  # };
  shelken = {
    wm.aerospace.enable = false;
    tools.hammerspoon.enable = true;
    secrets.enable = true;
  };
}
