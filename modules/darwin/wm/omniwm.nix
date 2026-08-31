{
  lib,
  mylib,
  config,
  ...
}:
let
  inherit (lib) mkIf;
  inherit (mylib) mkBoolOpt;
  cfg = config.shelken.wm.omniwm;
in
{
  options.shelken.wm.omniwm = {
    enable = mkBoolOpt false "Whether or not to enable omniwm.";
  };

  config = mkIf cfg.enable {
    homebrew = {
      taps = [
        {
          name = "BarutSRB/tap";
          trusted = true;
        }
      ];
      casks = [
        "omniwm"
      ];
    };
  };
}
