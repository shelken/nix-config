{
  lib,
  mylib,
  config,
  ...
}: let
  inherit (lib) mkIf;
  inherit (mylib) mkBoolOpt;
  cfg = config.shelken.creative.fcp;
in {
  options.shelken.creative.fcp = {
    enable = mkBoolOpt false "Whether or not to enable.";
  };

  config = mkIf cfg.enable {
    homebrew = {
      # masApps = {
      #   FinalCutPro = 424389933;
      # };
    };
  };
}
