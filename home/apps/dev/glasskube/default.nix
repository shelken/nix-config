{
  lib,
  mylib,
  config,
  pkgs,
  ...
}: let
  inherit (lib) mkIf;
  inherit (mylib) mkBoolOpt;
  cfg = config.shelken.dev.glasskube;
in {
  options.shelken.dev.glasskube = {
    enable = mkBoolOpt false "Whether or not to enable.";
  };

  config = mkIf cfg.enable {
    home.packages = with pkgs; [
      glasskube
    ];
    shelken.dev.minikube.enable = true;
  };
}
