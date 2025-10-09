{
  lib,
  mylib,
  config,
  ...
}:
let
  inherit (lib) mkIf;
  inherit (mylib) mkBoolOpt;
  cfg = config.shelken.tools.ntfs;
in
{
  options.shelken.tools.ntfs = {
    enable = mkBoolOpt false "Whether or not to enable.";
  };

  config = mkIf cfg.enable {
    homebrew = {
      casks = [
        "mounty" # for mount nfts disk
        "ntfs-3g-mac" # mounty need
        "macfuse" # mounty need
      ];
    };
  };
}
