{
  lib,
  mylib,
  config,
  # options,
  ...
}: let
  inherit (lib) mkIf;
  inherit (mylib) mkBoolOpt;
  cfg = config.shelken.wm.iceBar;
in {
  options.shelken.wm.iceBar = {
    enable = mkBoolOpt false "Whether or not to enable.";
  };

  config = mkIf cfg.enable {
    # 版本差异的
    homebrew = {
      casks = [
        "jordanbaird-ice"
      ];
      brews = [
      ];
    };
  };
}
