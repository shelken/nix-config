{
  pkgs,
  catppuccin-yazi,
  ...
}: {
  programs.yazi = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    settings = {
      manager = {
        ratio = [2 7 7];
      };
      preview = {
        tab_size = 3;
      };
    };
  };

  home.packages = with pkgs; [
    file
    fd
  ];

  xdg.configFile = {
    "yazi/theme.toml" = {
      source = catppuccin-yazi + "/themes/mocha.toml";
    };
  };
}
