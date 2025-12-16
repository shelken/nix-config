{ ... }:
{
  # programs.ssh = {
  #   inherit (myvars.networking.ssh) extraConfig;
  # };
  shelken = {
    secrets.enable = true;
    wm.aerospace.enable = true;
    dev.minikube.enable = true;
  };
}
