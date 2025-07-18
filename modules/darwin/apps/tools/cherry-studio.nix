{
  lib,
  mylib,
  config,
  ...
}: let
  inherit (lib) mkIf;
  inherit (mylib) mkBoolOpt;
  cfg = config.shelken.tools.cherry-studio;
in {
  options.shelken.tools.cherry-studio = {
    enable = mkBoolOpt false "Whether or not to enable.";
  };

  config = mkIf cfg.enable {
    homebrew = {
      casks = [
        "cherry-studio" # 官方客户端
      ];
    };
  };
}
