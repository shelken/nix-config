{
  lib,
  mylib,
  config,
  ...
}: let
  inherit (lib) mkIf;
  inherit (mylib) mkBoolOpt;
  cfg = config.shelken.suites.creative;
in {
  options.shelken.suites.creative = {
    enable = mkBoolOpt false "Whether or not to enable.";
  };

  config = mkIf cfg.enable {
    shelken.creative.fcp.enable = true;
  };
}
