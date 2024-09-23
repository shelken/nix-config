{...}: {
  # programs.ssh = {
  #   inherit (myvars.networking.ssh) extraConfig;
  # };
  shelken = {
    wm = {
      aerospace.enable = true;
      iceBar.enable = true;
    };
    dev = {
      minikube.enable = true;
    };
    secrets.enable = true;
  };
}
