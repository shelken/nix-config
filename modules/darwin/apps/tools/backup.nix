{
  lib,
  mylib,
  config,
  ...
}:
let
  inherit (lib) mkIf;
  inherit (mylib) mkBoolOpt;
  cfg = config.shelken.tools.backup;
in
{
  options.shelken.tools.backup = {
    enable = mkBoolOpt false "Whether or not to enable.";
  };

  config = mkIf cfg.enable {
    homebrew = {
      brews = [
        "restic"
      ];
      casks = [
        "restic-browser"
      ];
    };
  };
}
