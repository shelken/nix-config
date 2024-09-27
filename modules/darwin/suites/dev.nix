{
  lib,
  mylib,
  config,
  ...
}: let
  inherit (lib) mkIf;
  inherit (mylib) mkBoolOpt;
  cfg = config.shelken.suites.dev;
in {
  options.shelken.suites.dev = {
    enable = mkBoolOpt false "Whether or not to enable.";
  };

  config = mkIf cfg.enable {
    shelken.dev.container.enable = true;
    shelken.dev.ide.enable = true;
  };
}
