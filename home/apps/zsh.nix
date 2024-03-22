{
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    enableAutosuggestions = true;
    # enableSyntaxHighlighting = true;
    syntaxHighlighting.enable = true;
    shellAliases = {
      ll = "eza --icons -l -T -L=2";
      #update = "sudo nixos-rebuild switch";
      proxy = "export https_proxy=http://192.168.6.1:7890 http_proxy=http://192.168.6.1:7890";
      unproxy = "unset https_proxy http_proxy";
    };
    history = {
      size = 10000;
    };
    oh-my-zsh = {
      enable = true;
      plugins = [
        "docker-compose"
        "docker"
      ];
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
