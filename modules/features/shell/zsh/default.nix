{ config, ... }:
{
  flake.modules.homeManager.core.imports = [ config.flake.modules.homeManager.zsh ];

  flake.modules.homeManager.zsh =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      zshDotDir = "${config.xdg.configHome}/zsh";
    in
    {
      home.sessionPath = [ "$HOME/.local/bin" ];

      programs.zsh = {
        enable = true;
        dotDir = zshDotDir;
        # Home Manager 默认早于 oh-my-zsh/fzf-tab 加载；改为 plugins 控制 ZLE 包装顺序。
        autosuggestion.enable = false;
        syntaxHighlighting.enable = true;
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
          plugins = [
            "sudo"
          ];
          # 禁用 oh-my-zsh 的 self-insert/bracketed-paste magic，避免长输入触发 ZLE 重算烧 CPU。
          extraConfig = ''
            DISABLE_MAGIC_FUNCTIONS=true
          '';
        };
        initContent =
          let
            firstInit = lib.mkBefore ''

              # mise 的 shim 目录全局共用一份，但版本声明是项目级的。
              # oh-my-zsh 的 helm/fluxcd 等插件在加载时探测命令，项目外调用会命中
              # 孤儿 shim 并报 "No version is set for shim"。此处先剔除，插件即跳过。
              path=(''${path:#''${HOME}/.local/share/mise/shims})

              setopt AUTO_CD
              setopt INTERACTIVE_COMMENTS
              setopt HIST_FCNTL_LOCK
              setopt SHARE_HISTORY
              setopt EXTENDED_HISTORY
              unsetopt AUTO_REMOVE_SLASH
            '';
            defaultInit = ''
              bindkey '^f' autosuggest-accept
              zstyle ':completion:*:just:*' sort false
              zstyle ':completion:*:git-checkout:*' sort false
              zstyle ':completion:*:descriptions' format '[%d]'
              zstyle ':completion:*:*:*:*:*' menu no
              zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza -1 --color=always $realpath'
              zstyle ':fzf-tab:*' switch-group '<' '>'
            '';
          in
          lib.mkMerge [
            firstInit
            defaultInit
          ];
        plugins = [
          {
            name = "fzf-key-bindings";
            src = pkgs.fzf;
            file = "share/fzf/key-bindings.zsh";
          }
          {
            name = "fzf-tab";
            src = pkgs.zsh-fzf-tab;
            file = "share/fzf-tab/fzf-tab.plugin.zsh";
          }
          {
            name = "zsh-autosuggestions";
            src = pkgs.zsh-autosuggestions;
            file = "share/zsh-autosuggestions/zsh-autosuggestions.zsh";
          }
        ];
      };
    };
}
