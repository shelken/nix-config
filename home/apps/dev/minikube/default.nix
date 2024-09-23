{
  lib,
  mylib,
  config,
  pkgs,
  ...
}: let
  inherit (lib) mkIf;
  inherit (mylib) mkBoolOpt;
  cfg = config.shelken.dev.minikube;
in {
  options.shelken.dev.minikube = {
    enable = mkBoolOpt false "Whether or not to enable.";
  };

  config = mkIf cfg.enable {
    home.packages = with pkgs; [
      minikube
      kubectl
    ];
    programs.k9s.enable = true;
  };
}
