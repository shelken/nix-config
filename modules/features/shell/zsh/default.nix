{ config, ... }:
{
  flake.modules.homeManager.core.imports = [ config.flake.modules.homeManager.zsh ];
  flake.modules.homeManager.tui.imports = [ config.flake.modules.homeManager.zsh-dev ];

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
            "docker"
            "rsync"
            "sudo"
            "ssh"
            "tailscale"
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
            functionsInit = ''
              fpath=( ${functionsDir} $fpath )
              autoload -Uz ${functionsDir}/*(:t)
              # compinit 已由 oh-my-zsh 提前运行，手动注册 functions/_* 补全函数
              for _hmf in ${functionsDir}/_*(N:t); do
                compdef "$_hmf" "''${_hmf#_}"
              done
              unset _hmf
            '';
            defaultInit = ''
              bindkey '^f' autosuggest-accept
            '';
          in
          lib.mkMerge [
            firstInit
            functionsInit
            defaultInit
            (lib.mkOrder 1001 initContent)
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

      programs.fzf = {
        enable = true;
        # HM 的 fzf zsh 集成会加载 completion.zsh，在 fzf-tab 之后覆写 ^I（Tab）绑定；只保留上面手动加载的 key-bindings.zsh
        enableZshIntegration = false;
      };

      fonts.fontconfig = {
        enable = true;
        defaultFonts.monospace = [
          myvars.fontFamilies.monospace
          myvars.fontFamilies.cjkMonospace
        ];
      };

      programs.bash = {
        enable = true;
        enableCompletion = true;
        bashrcExtra = envExtra;
        initExtra = lib.mkOrder 1001 initContent;
      };

      programs.zsh.envExtra = envExtra;

      home.shellAliases = shellAliases // {
        ll = "eza --icons -l -T -L=1";
      };

      programs.eza = {
        enable = true;
        git = true;
        icons = "auto";
      };

      programs.bat = {
        enable = true;
        config = {
          pager = "less -FR";
        };
      };

      # HM 的 batCache 每次激活都 `bat cache --build` 并打印三行。catppuccin 经 programs.bat.themes
      # 注入了自定义主题，bat 只从缓存读自定义资源，缓存必须保留；构建只要约 0.3s，所以每次重建，只丢弃 stdout
      home.activation.batCache = lib.mkForce (
        lib.hm.dag.entryAfter [ "linkGeneration" ] ''
          (
            export XDG_CACHE_HOME=${lib.escapeShellArg config.xdg.cacheHome}
            # 在空目录里构建，规避 ~/cache 存在时的失败：https://github.com/sharkdp/bat/issues/1726
            cd "${pkgs.emptyDirectory}"
            run ${lib.getExe config.programs.bat.package} cache --build > /dev/null
          )
        ''
      );

      programs.zoxide = {
        enable = true;
        enableBashIntegration = true;
        enableZshIntegration = true;
        enableNushellIntegration = true;
      };
    };

  flake.modules.homeManager.zsh-dev = {
    programs.zsh.oh-my-zsh.plugins = [
      "azure"
      "fluxcd"
      "gitignore"
      "golang"
      "helm"
      "httpie"
      "kubectl"
      "mvn"
      "pip"
      "qrcode"
      "rclone"
      "terraform"
    ];
    programs.fzf.defaultCommand = "fd --type f";
  };
}
