{
  pkgs,
  lib,
  ...
}: let
  zshDotDir = ".config/zsh";
in {
  programs.zsh = {
    enable = true;
    # 自定义配置目录
    dotDir = zshDotDir;
    enableCompletion = true;
    autosuggestion.enable = true;
    # enableSyntaxHighlighting = true;
    syntaxHighlighting.enable = true;
    initExtraFirst = ''
      setopt AUTO_CD
      setopt INTERACTIVE_COMMENTS
      setopt HIST_FCNTL_LOCK
      setopt HIST_IGNORE_ALL_DUPS
      setopt SHARE_HISTORY
      unsetopt AUTO_REMOVE_SLASH
    '';
    shellAliases = {
      ll = "eza --icons -la -T -L=1";
      #update = "sudo nixos-rebuild switch";
      proxy = "export https_proxy=http://192.168.6.226:7896 http_proxy=http://192.168.6.226:7896";
      unproxy = "unset https_proxy http_proxy";
    };
    history = {
      size = 10000;
      save = 10000;
    };
    oh-my-zsh = {
      enable = true;
      plugins = [
        # "docker-comose"
        "docker"
      ];
      # custom = omzCustomPath;
    };
    initExtra = ''
      bindkey '^f' autosuggest-accept

      # p10k custome
      POWERLEVEL9K_OS_ICON_CONTENT_EXPANSION='🤘'

      ################
      # 特定机器配置 #
      ################
      [[ -s "$HOME/.specific.zsh" ]] && source $HOME/.specific.zsh
    '';
    plugins = [
      {
        # A prompt will appear the first time to configure it properly
        # make sure to select MesloLGS NF as the font in Konsole
        name = "powerlevel10k";
        src = pkgs.zsh-powerlevel10k;
        file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
      }
      {
        name = "powerlevel10k-config";
        src = lib.cleanSource ./p10k;
        file = "p10k.zsh";
      }
    ];
  };

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
  };

  fonts.fontconfig.enable = true;
  home.packages = with pkgs; [
    # Meslo Nerd Font patched for Powerlevel10k
    # Restart Konsole and configure it (profile) to choose MesloLGS NF
    meslo-lgs-nf
  ];
}
