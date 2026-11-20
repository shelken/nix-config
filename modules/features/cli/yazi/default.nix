{ config, ... }:
{
  flake.modules.homeManager.tui.imports = [ config.flake.modules.homeManager.yazi ];

  flake.modules.homeManager.yazi =
    {
      config,
      mylib,
      pkgs,
      ...
    }:
    {
      programs.yazi = {
        enable = true;
        enableZshIntegration = true;
        enableBashIntegration = true;
        shellWrapperName = "yy";
        plugins = {
          piper = pkgs.yaziPlugins.piper;
          projects = pkgs.yaziPlugins.projects;
        };
      };

      home.packages = with pkgs; [
        file
        exiftool
        mediainfo
        glow
      ];

      xdg.configFile = {
        "yazi/yazi.toml" = mylib.mkConfigFile config ./yazi.toml;
        "yazi/keymap.toml" = mylib.mkConfigFile config ./keymap.toml;
        "yazi/vfs.toml" = mylib.mkConfigFile config ./vfs.toml;
        "yazi/init.lua" = mylib.mkConfigFile config ./init.lua;
      };
    };
}
