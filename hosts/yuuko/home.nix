{...}: {
  # programs.ssh = {
  #   inherit (myvars.networking.ssh) extraConfig;
  # };
  shelken = {
    wm.aerospace.enable = true;
    secrets = true;
  };
}
