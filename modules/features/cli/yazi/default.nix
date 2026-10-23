# yazi：文件管理器（home/base/core/yazi 迁入）
{
  flake.modules.homeManager.yazi =
    {
      config,
      mylib,
      pkgs,
      sources,
      ...
    }:
    {
      programs.yazi = {
        enable = true;
        enableZshIntegration = true;
        enableBashIntegration = true;
        shellWrapperName = "yy";
        plugins = {
          piper = "${sources.yazi-plugins.src}/piper.yazi";
          projects = "${sources.projects-yazi.src}";
          # mime = "${sources.yazi-plugins.src}/mime.yazi";
        };
      };

      home.packages = with pkgs; [
        file
        fd
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
