{...}: {
  # programs.ssh = {
  #   inherit (myvars.networking.ssh) extraConfig;
  # };
  shelken = {
    wm = {
      aerospace.enable = true;
      iceBar.enable = true;
    };
    secrets.enable = true;
  };
}
