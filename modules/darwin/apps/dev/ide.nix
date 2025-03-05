{
  lib,
  mylib,
  config,
  ...
}: let
  inherit (lib) mkIf;
  inherit (mylib) mkBoolOpt;
  cfg = config.shelken.dev.ide;
in {
  options.shelken.dev.ide = {
    enable = mkBoolOpt false "Whether or not to enable.";
  };

  config = mkIf cfg.enable {
    homebrew = {
      casks = [
        "visual-studio-code" # vs-code
        "intellij-idea" # IDEA
        "zed"
        "cursor"
        "trae"
      ];
    };
  };
}
