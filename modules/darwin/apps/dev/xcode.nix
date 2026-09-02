{
  lib,
  mylib,
  config,
  ...
}:
let
  inherit (lib) mkIf;
  inherit (mylib) mkBoolOpt;
  cfg = config.shelken.dev.xcode;
in
{
  options.shelken.dev.xcode = {
    enable = mkBoolOpt false "Whether or not to enable.";
  };

  config = mkIf cfg.enable {
    homebrew = {
      masApps = {
        Xcode = 497799835;
      };
    };
  };
}
