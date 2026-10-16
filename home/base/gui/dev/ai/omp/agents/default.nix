{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkIf;
  cfg = config.shelken.dev.ai;
  agentsDir = pkgs.callPackage ./dir.nix { };
in
{
  config = mkIf cfg.enable {
    home.file.".omp/agent/agents".source = agentsDir;
  };
}
