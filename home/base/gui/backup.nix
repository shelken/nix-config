{
  mylib,
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.shelken.tools.backup;
in
{
  options.shelken.tools.backup = {
    enable = mylib.mkBoolOpt false "Whether or not use.";
  };
  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      kopia
      # kopia-ui
    ];
  };
}
