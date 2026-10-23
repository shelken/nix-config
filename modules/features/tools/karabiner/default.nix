# karabiner：rsync 同步键位配置到 ~/.config/karabiner
# 可选功能，需要时主机 imports = [ self.modules.darwin.karabiner ]
{
  flake.modules.homeManager.karabiner =
    {
      pkgs,
      config,
      lib,
      ...
    }:
    {
      home.activation.SyncKarabinerConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        ${pkgs.rsync}/bin/rsync -az --delete --chmod=F600 --mkpath \
        ${./karabiner.json} \
        ${config.xdg.configHome}/karabiner/karabiner.json
      '';
    };
}
