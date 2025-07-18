{
  lib,
  mylib,
  config,
  ...
}: let
  inherit (lib) mkIf;
  inherit (mylib) mkBoolOpt;
  cfg = config.shelken.homelab.server;
in {
  options.shelken.homelab.server = {
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
