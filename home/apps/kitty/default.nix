{
  myvars,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) concatStrings;
  theme = "Catppuccin-${myvars.catppuccin_flavor}.conf";
  origin_file = builtins.readFile ./kitty.conf;
  shell_integration = "no-rc no-cursor"; # no-cursor make `cursor_shape` config works
  shellIntegrationInit = {
    bash = ''
      if test -n "$KITTY_INSTALLATION_DIR"; then
        export KITTY_SHELL_INTEGRATION="${shell_integration}"
        source "$KITTY_INSTALLATION_DIR/shell-integration/bash/kitty.bash"
      fi
    '';
    zsh = ''
      if test -n "$KITTY_INSTALLATION_DIR"; then
        export KITTY_SHELL_INTEGRATION="${shell_integration}"
        autoload -Uz -- "$KITTY_INSTALLATION_DIR"/shell-integration/zsh/kitty-integration
        kitty-integration
        unfunction kitty-integration
      fi
    '';
  };
  kitty-icon-pkgs = pkgs.fetchFromGitHub {
    owner = "DinkDonk";
    repo = "kitty-icon";
    rev = "0bdece53";
    hash = "sha256-TLltUcfJpY+3rwvHYgtN4zBpbBnLBYyzDu90UMnxwoc=";
  };
in {
  # programs.kitty = {
  #   enable = false; # 用 homebrew 安装
  #   theme = theme;
  #   shellIntegration.mode = shell_integration;
  #   extraConfig = builtins.readFile ./kitty.conf;
  #   environment = {
  #     # not use `xterm-kitty`
  #     # "TERM" = "xterm-256color";
  #   };
  # };

  xdg.configFile."kitty/kitty.conf" = {
    text = concatStrings [
      ''
        # 主题配色
        include ${pkgs.kitty-themes}/share/kitty-themes/themes/${theme}
      ''
      ''
        # Shell integration
        shell_integration ${shell_integration}
      ''
      origin_file
    ];
  };
  xdg.configFile."kitty/kitty.app.png" = {
    source = "${kitty-icon-pkgs}/kitty-light.png";
  };

  programs.zsh.initExtra = shellIntegrationInit.zsh;
  programs.bash.initExtra = shellIntegrationInit.bash;

  home.sessionVariables = {
    TERM = "xterm-256color";
  };
}
