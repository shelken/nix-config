{
  config,
  pkgs,
  sources,
  ...
}:
let
  yaziCfgDir = "${config.home.homeDirectory}/nix-config/home/base/core/yazi";
in
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
      source = config.lib.file.mkOutOfStoreSymlink "${yaziCfgDir}/yazi.toml";
      force = true;
    };
    "yazi/keymap.toml" = {
      source = config.lib.file.mkOutOfStoreSymlink "${yaziCfgDir}/keymap.toml";
      force = true;
    };
    "yazi/vfs.toml" = {
      source = config.lib.file.mkOutOfStoreSymlink "${yaziCfgDir}/vfs.toml";
      force = true;
    };
    "yazi/init.lua" = {
      source = config.lib.file.mkOutOfStoreSymlink "${yaziCfgDir}/init.lua";
      force = true;
    };
  };
}
