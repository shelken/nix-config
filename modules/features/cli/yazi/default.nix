# yazi：文件管理器
{ config, ... }:
{
  flake.modules.homeManager.core.imports = [ config.flake.modules.homeManager.yazi ];

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
        # fd 由共享工具登记表提供（shelken.dev.tools，ADR 0003）
        exiftool
        mediainfo
        # for markdown preview
        glow
        # for fg.yazi
        # fzf
        # ripgrep
        # bat
      ];

      xdg.configFile = {
        "yazi/yazi.toml" = mylib.mkConfigFile config ./yazi.toml;
        "yazi/keymap.toml" = mylib.mkConfigFile config ./keymap.toml;
        "yazi/vfs.toml" = mylib.mkConfigFile config ./vfs.toml;
        "yazi/init.lua" = mylib.mkConfigFile config ./init.lua;
      };
    };
}
