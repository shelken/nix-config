{
  lib,
  mylib,
  config,
  # options,
  ...
}: let
  inherit (lib) mkIf;
  inherit (mylib) mkBoolOpt;
  cfg = config.shelken.wm.aerospace;
in {
  options.shelken.wm.aerospace = {
    enable = mkBoolOpt false "Whether or not to enable aerospace.";
  };

  config = mkIf cfg.enable {
    # 版本差异的
    homebrew = {
      casks = [
        "aerospace"
      ];
    };
  };
}
