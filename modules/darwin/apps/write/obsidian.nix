{
  lib,
  mylib,
  config,
  ...
}: let
  inherit (lib) mkIf;
  inherit (mylib) mkBoolOpt;
  cfg = config.shelken.write.obsidian;
in {
  options.shelken.write.obsidian = {
    enable = mkBoolOpt false "Whether or not to enable.";
  };

  config = mkIf cfg.enable {
    # 版本差异的
    homebrew = {
      casks = [
        "obsidian"
      ];
    };
  };
}
