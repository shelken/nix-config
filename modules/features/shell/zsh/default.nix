# zsh：shell、oh-my-zsh、fzf
{ config, ... }:
{
  flake.modules.homeManager.core.imports = [ config.flake.modules.homeManager.zsh ];

  flake.modules.homeManager.zsh =
    {
      pkgs,
      lib,
      config,
      myvars,
      ...
    }:
    let
      zshDotDir = "${config.xdg.configHome}/zsh";
      functionsDir = "${zshDotDir}/functions";
      functionFiles = lib.filesystem.listFilesRecursive ./functions;

      proxy_fun = ''
        function proxy() {
          local default_proxy="http://127.1:7890"
          local final_proxy="''${PROXY:-$default_proxy}"

          export HTTP_PROXY="$final_proxy"
          export HTTPS_PROXY="$final_proxy"
          export http_proxy="$final_proxy"
          export https_proxy="$final_proxy"

          echo "✅ 代理设置完成："
          echo "  HTTP_PROXY:  $HTTP_PROXY"
          echo "  HTTPS_PROXY: $HTTPS_PROXY"
        }
        function unproxy() {
          unset PROXY https_proxy http_proxy HTTPS_PROXY HTTP_PROXY
        }
      '';

      shellAliases = {
        urldecode = "python3 -c 'import sys, urllib.parse as ul; print(ul.unquote_plus(sys.stdin.read()))'";
        urlencode = "python3 -c 'import sys, urllib.parse as ul; print(ul.quote_plus(sys.stdin.read()))'";

        mkdir = "mkdir -p";
      };

      localBin = "${config.home.homeDirectory}/.local/bin";
      goBin = "${config.home.homeDirectory}/go/bin";
      rustBin = "${config.home.homeDirectory}/.cargo/bin";
      npmBin = "${config.home.homeDirectory}/.npm-global/bin";
      bunBin = "${config.home.homeDirectory}/.cache/.bun/bin";
      krewBin = "${config.home.homeDirectory}/.krew/bin";
      lmstudioBin = "${config.home.homeDirectory}/.lmstudio/bin";

      envExtra = ''
        export PATH="$PATH:${localBin}:${goBin}:${rustBin}:${bunBin}:${npmBin}:${krewBin}:${lmstudioBin}"
      '';

      initContent = ''
        ${proxy_fun}
      '';
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
        # Home Manager 默认早于 oh-my-zsh/fzf-tab 加载；改为 plugins 控制 ZLE 包装顺序。
        autosuggestion.enable = false;
        # 语法高亮保持 Home Manager 默认末尾加载。
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
          # 禁用 oh-my-zsh 的 self-insert/bracketed-paste magic，避免长输入触发 ZLE 重算烧 CPU。
          extraConfig = ''
            DISABLE_MAGIC_FUNCTIONS=true
          '';
          # custom = omzCustomPath;
        };
        initContent =
          let
            firstInit = lib.mkBefore ''
              # 性能分析
              # zmodload zsh/zprof

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
            functionsInit = ''
              fpath=( ${functionsDir} $fpath )
              autoload -Uz ${functionsDir}/*(:t)
              # compinit 已由 oh-my-zsh 提前运行，手动注册 functions/_* 补全函数
              # 命名规范：_<command>.zsh → _<command>，自动 compdef _<command> <command>
              for _hmf in ${functionsDir}/_*(N:t); do
                compdef "$_hmf" "''${_hmf#_}"
              done
              unset _hmf
            '';
            defaultInit = ''
              bindkey '^f' autosuggest-accept

              # K8s Pod 交互式路径选择 widget
              zle -N kube-pod-path-widget
              bindkey '^k' kube-pod-path-widget
            '';
          in
          lib.mkMerge [
            firstInit
            functionsInit
            defaultInit
            # PATH、代理函数
            (lib.mkOrder 1001 initContent)
          ];
        plugins = [
          # oh-my-zsh/compinit
          #    -> fzf key bindings, 不含 Tab completion
          #    -> fzf-tab
          #    -> zsh-autosuggestions
          #    -> zsh-syntax-highlighting
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

      programs.fzf = {
        enable = true;
        # fzf --zsh 会在 fzf-tab 之后把 Tab 绑到 fzf-completion；这里只保留上面的 key-bindings。
        enableZshIntegration = false;
        defaultCommand = "fd --type f";
      };

      fonts.fontconfig = {
        enable = true;
        defaultFonts.monospace = [
          myvars.fontFamilies.monospace
          myvars.fontFamilies.cjkMonospace
        ];
      };

      # bash：补全与 PATH、代理函数
      programs.bash = {
        enable = true;
        enableCompletion = true;
        bashrcExtra = envExtra;
        initExtra = lib.mkOrder 1001 initContent;
      };

      # zsh 追加：PATH 环境变量与别名（initContent 已并入上方 mkMerge）
      programs.zsh.envExtra = envExtra;

      home.shellAliases = shellAliases // {
        ll = "eza --icons -l -T -L=1";
      };

      # ls 替代：现代 ls
      # A modern replacement for 'ls'
      # useful in bash/zsh prompt, not in nushell.
      programs.eza = {
        enable = true;
        git = true;
        icons = "auto";
      };

      # a cat(1) clone with syntax highlighting and Git integration.
      # cat 替代
      programs.bat = {
        enable = true;
        config = {
          pager = "less -FR";
        };
      };

      # zoxide is a smarter cd command, inspired by z and autojump.
      # It remembers which directories you use most frequently,
      # so you can "jump" to them in just a few keystrokes.
      # zoxide works on all major shells.
      #
      #   z foo              # cd into highest ranked directory matching foo
      #   z foo bar          # cd into highest ranked directory matching foo and bar
      #   z foo /            # cd into a subdirectory starting with foo
      #   z ..               # cd one level up
      #   z -                # cd into previous directory
      #
      #   zi foo             # cd with interactive selection (using fzf)
      #
      #   z foo<SPACE><TAB>  # show interactive completions (zoxide v0.8.0+, bash 4.4+/fish/zsh only)
      # 快速跳转
      programs.zoxide = {
        enable = true;
        enableBashIntegration = true;
        enableZshIntegration = true;
        enableNushellIntegration = true;
      };
    };
}
