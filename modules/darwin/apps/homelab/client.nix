{
  lib,
  mylib,
  config,
  ...
}: let
  inherit (lib) mkIf;
  inherit (mylib) mkBoolOpt;
  cfg = config.shelken.homelab.client;
in {
  options.shelken.homelab.client = {
    enable = mkBoolOpt false "Whether or not to enable.";
  };

  config = mkIf cfg.enable {
    # 版本差异的
    homebrew = {
      brews = [
        "lima"
      ];
    };
  };
}
