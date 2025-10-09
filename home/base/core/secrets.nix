{
  mylib,
  config,
  lib,
  ...
}:
let
  inherit (mylib) mkBoolOpt;
  inherit (lib) mkIf;
  cfg = config.shelken.secrets;
in
{
  options.shelken.secrets = {
    enable = mkBoolOpt false "Whether or not use secrets";
  };
  config = mkIf cfg.enable {
  };
}
