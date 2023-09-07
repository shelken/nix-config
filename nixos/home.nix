{
  config,
  pkgs,
  ...
}: {
  home.username = "shelken";
  home.homeDirectory = "/home/shelken";
  home.stateVersion = "23.05";
  home.packages = with pkgs; [
    #zsh
    htop
  ];
  # 配置zsh
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    enableAutosuggestions = true;
    enableSyntaxHighlighting = true;
    oh-my-zsh = {
      enable = true;
      plugins = ["docker-compose" "docker"];
      theme = "dst";
    };
    initExtra = ''
      bindkey '^f' autosuggest-accept
    '';
  };

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
  };
}
