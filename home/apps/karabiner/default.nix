{
  pkgs,
  config,
  lib,
  ...
}: let
  config-path = ./config;
in {
  # xdg.configFile."karabiner/karabiner.json" = {
  #   source = ./config/karabiner.json;
  # };
  home.activation.SyncKarabinerConfig = lib.hm.dag.entryAfter ["writeBoundary"] ''
    ${pkgs.rsync}/bin/rsync -az --delete --chmod=F600 \
    ${config-path}/karabiner.json \
    ${config.xdg.configHome}/karabiner/karabiner.json
  '';
}
