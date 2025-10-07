{...}: {
  # programs.ssh = {
  #   inherit (myvars.networking.ssh) extraConfig;
  # };
  shelken = {
    tools.hammerspoon.enable = true;
    dev.minikube.enable = true;
    secrets.enable = true;
  };
}
