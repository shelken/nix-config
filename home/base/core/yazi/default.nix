{
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
    "yazi/yazi.toml" = {
      source = ./yazi.toml;
    };
    "yazi/keymap.toml" = {
      source = ./keymap.toml;
    };
    "yazi/vfs.toml" = {
      source = ./vfs.toml;
    };
    "yazi/init.lua" = {
      source = ./init.lua;
    };
  };
}
