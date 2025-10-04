{
  lib,
  mylib,
  config,
  ...
}: let
  inherit (lib) mkIf;
  inherit (mylib) mkBoolOpt;
  cfg = config.shelken.network.fl-clash;
in {
  options.shelken.network.fl-clash = {
    enable = mkBoolOpt false "Whether or not to enable.";
  };

  config = mkIf cfg.enable {
    homebrew = {
      taps = [
        "shelken/tap"
      ];
      casks = [
        "fl-clash"
      ];
      brews = [
      ];
    };
  };
}
