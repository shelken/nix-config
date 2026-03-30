{
  pkgs,
  lib,
  config,
  ...
}:
let
  zshDotDir = "${config.xdg.configHome}/zsh";
  functionsDir = "${zshDotDir}/functions";
  functionFiles = lib.filesystem.listFilesRecursive ./functions;
in
{
  xdg.configFile = lib.listToAttrs (
    map (f: {
      name = "zsh/functions/${lib.removeSuffix ".zsh" (baseNameOf f)}";
      value = {
        source = f;
      };
    }) (lib.filter (f: lib.hasSuffix ".zsh" (toString f)) functionFiles)
  );

  programs.zsh = {
    enable = true;
    # 自定义配置目录
    dotDir = zshDotDir;
    # 自动补全 默认不需要，如果使用omz的话
    # enableCompletion = true;
    # 自动提示
    autosuggestion.enable = true;
    # 语法高亮
    syntaxHighlighting.enable = true;
    # https://home-manager-options.extranix.com/?query=zsh.history
    history = {
      size = 30000;
      save = 30000;
      extended = true;
      ignoreAllDups = true;
      append = true;
      share = true;
    };
    oh-my-zsh = {
      enable = true;
      # ref: https://github.com/ohmyzsh/ohmyzsh/blob/master/plugins
      plugins = [
        "azure"
        # "docker-comose"
        "docker"
        "fluxcd"
        "gitignore" # 命令gi; https://github.com/ohmyzsh/ohmyzsh/blob/master/plugins/gitignore/README.md
        "golang" # 自动补全以及alias; https://github.com/ohmyzsh/ohmyzsh/blob/master/plugins/golang/README.md
        "helm"
        "httpie" # 命令http; 自动补全; https://github.com/ohmyzsh/ohmyzsh/blob/master/plugins/httpie/README.md
        "kubectl"
        "minikube"
        "mvn" # 自动补全及alias; https://github.com/ohmyzsh/ohmyzsh/blob/master/plugins/mvn/README.md
        "pip"
        "qrcode" # https://github.com/ohmyzsh/ohmyzsh/blob/master/plugins/qrcode/README.md
        "rclone"
        "rsync"
        "sudo" # https://github.com/ohmyzsh/ohmyzsh/blob/master/plugins/sudo/README.md
        "ssh"
        "tailscale"
        "terraform"
      ];
      # custom = omzCustomPath;
    };
    initContent =
      let
        firstInit = lib.mkBefore ''
          # 性能分析
          # zmodload zsh/zprof

          setopt AUTO_CD
          setopt INTERACTIVE_COMMENTS
          setopt HIST_FCNTL_LOCK
          setopt SHARE_HISTORY
          setopt EXTENDED_HISTORY
          unsetopt AUTO_REMOVE_SLASH
        '';
        functionsInit = ''
          fpath=( ${functionsDir} $fpath )
          autoload -Uz ${functionsDir}/*(:t)
        '';
        defaultInit = ''
          bindkey '^f' autosuggest-accept

          # p10k custom
          POWERLEVEL9K_OS_ICON_CONTENT_EXPANSION='🤘'
          # mitigation: https://github.com/romkatv/powerlevel10k?tab=readme-ov-file#mitigation
          POWERLEVEL9K_TERM_SHELL_INTEGRATION=true
        '';
      in
      lib.mkMerge [
        firstInit
        functionsInit
        defaultInit
      ];
    plugins = [
      {
        # A prompt will appear the first time to configure it properly
        # make sure to select MesloLGS NF as the font in Konsole
        name = "powerlevel10k";
        src = pkgs.zsh-powerlevel10k;
        file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
      }
      {
        name = "fzf-tab";
        src = pkgs.zsh-fzf-tab;
        file = "share/fzf-tab/fzf-tab.plugin.zsh";
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
    defaultCommand = "fd --type f";
  };

  fonts.fontconfig.enable = true;
  home.packages = with pkgs; [
    # Meslo Nerd Font patched for Powerlevel10k
    # Restart Konsole and configure it (profile) to choose MesloLGS NF
    meslo-lgs-nf
  ];
}
