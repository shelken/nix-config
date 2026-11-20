{ config, ... }:
{
  flake.modules.homeManager.tui.imports = [ config.flake.modules.homeManager.herdr ];

  flake.modules.darwin.gui.imports = [ config.flake.modules.darwin.herdr-app ];

  flake.modules.darwin.herdr-app.homebrew = {
    casks = [
      "herdr-app"
    ];
  };

  flake.modules.homeManager.herdr-app =
    {
      config,
      lib,
      mylib,
      ...
    }:
    {
      xdg.configFile."herdr-app/settings.json" = mylib.mkConfigFile config ./herdr-app/settings.json;

      home.file.".herdr/worktrees".source =
        config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/Code/worktrees";
      home.activation.herdrWorktrees = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run mkdir -p "$HOME/Code/worktrees"
      '';
    };

  flake.modules.homeManager.herdr =
    {
      config,
      mylib,
      ...
    }:
    {
      xdg.configFile."herdr/config.toml" = mylib.mkConfigFile config ./config.toml;

      xdg.configFile."herdr/plugins/config/herdr-lazy/plugins.list" =
        mylib.mkConfigFile config ./plugins.list;
      xdg.configFile."herdr/plugins/config/herdr-lazy/plugins.lock" =
        mylib.mkConfigFile config ./plugins.lock;

      home.file.".local/bin/herdr-lazy" = mylib.mkConfigFile config ./bin/herdr-lazy;
    };
}
