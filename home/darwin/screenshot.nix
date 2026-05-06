{
  config,
  lib,
  mylib,
  ...
}:
let
  cfg = config.shelken.tools.screenshot;
in
{
  options.shelken.tools.screenshot = {
    enable = mylib.mkBoolOpt false "Whether or not to enable.";
  };
  config = lib.mkIf cfg.enable {
  };
}
