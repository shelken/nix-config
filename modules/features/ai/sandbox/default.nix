{
  flake.modules.homeManager.ai =
    {
      config,
      lib,
      mylib,
      pkgs,
      nixpkgs,
      extendModules,
      ...
    }:
    let
      msbHome = "${config.home.homeDirectory}/Data/sandboxes/msb";
      # 宿主共用 Linux mise 目录：data 与 cache 分离，guest 侧固定挂到 /opt/sandbox-mise
      sharedMiseDir = "${config.home.homeDirectory}/Data/sandboxes/mise/aarch64-linux";
      msbConfig = (pkgs.formats.json { }).generate "microsandbox-config.json" {
        version = 1;
        home = msbHome;
        paths.cache = "${config.home.homeDirectory}/.cache/microsandbox";
        sandbox_defaults.disable_metrics_sample = true;
      };

      gitConfig = (pkgs.formats.gitIni { }).generate "sandbox-git-config" {
        user = config.programs.git.settings.user;
        credential."https://github.com".helper = "!gh auth git-credential";
        url."https://github.com/".insteadOf = "git@github.com:";
      };

      generator = import ./_generator.nix {
        inherit
          pkgs
          lib
          config
          nixpkgs
          gitConfig
          ;
      };
      sandboxConfig = generator.sandboxConfig;

      linuxSystem = "${pkgs.stdenv.hostPlatform.parsed.cpu.name}-linux";
      linuxPkgs = nixpkgs.legacyPackages.${linuxSystem};

      launcher = import ./_launcher.nix {
        inherit
          pkgs
          linuxPkgs
          gitConfig
          ;
        inherit (generator) guestBinPath;
      };

      sb = import ./_sb.nix {
        inherit
          pkgs
          msbConfig
          msbHome
          launcher
          sandboxConfig
          ;
        inherit (generator) guestStatus;
        defaultConf = ./sb.yaml;
      };
    in
    {
      options.shelken.dev.ai.sandbox.enable =
        mylib.mkBoolOpt false "Whether to install the agent sandbox.";

      config = lib.mkIf config.shelken.dev.ai.sandbox.enable {
        # 可写根与声明配置的一致性：launcher 只执行发布清单，不兜底，所以在构建期拒绝不合法的组合。
        # .config/<X> 走 XDG（/data/xdg/config），不属于任何根
        assertions =
          let
            roots = config.shelken.dev.sandbox.writableRoots;
            under = root: p: p == root || lib.hasPrefix "${root}/" p;
            targets = lib.concatMap (tool: builtins.attrNames tool.files) (
              builtins.attrValues config.shelken.dev.tools
            );
          in
          [
            {
              assertion = lib.all (
                r:
                r != ""
                && !(lib.hasPrefix "/" r)
                && !(lib.hasSuffix "/" r)
                && !(lib.hasPrefix ".config/" r)
                && !(builtins.elem ".." (lib.splitString "/" r))
              ) roots;
              message = "shelken.dev.sandbox.writableRoots: 每项必须是 $HOME 下的相对路径，不能为空、以 / 结尾、含 .. 或落在 .config/ 下：${builtins.toJSON roots}";
            }
            {
              assertion = lib.all (a: lib.all (b: a == b || !(under a b)) roots) roots;
              message = "shelken.dev.sandbox.writableRoots: 根之间不能嵌套：${builtins.toJSON roots}";
            }
            {
              assertion = lib.all (t: lib.hasPrefix ".config/" t || lib.any (r: under r t) roots) targets;
              message = "shelken.dev.tools.*.files 的目标必须落在某个 writableRoots 下或位于 .config/ 下，否则沙箱无处挂载：${
                builtins.toJSON (
                  builtins.filter (t: !(lib.hasPrefix ".config/" t || lib.any (r: under r t) roots)) targets
                )
              }";
            }
          ];

        shelken.dev.sandbox.hostCommands = {
          sb = "sb 是宿主沙箱管理 CLI，沙箱内部无法嵌套管理沙箱 VM";
          just = "just hm / just sw 是宿主系统切换命令，沙箱内无法修改宿主系统配置";
        };
        programs.mise.globalConfig.tools.microsandbox = "0.7.7";

        home.sessionVariables = {
          MSB_HOME = msbHome;
          MSB_CONFIG_PATH = "${msbConfig}";
          # sb sync 宿主写锁目录（共用 mise 层）
          SB_MISE_LOCK_DIR = sharedMiseDir;
          # generate_msb_config 注入共用挂载时读取的宿主真实路径
          SB_MISE_HOST_DIR = sharedMiseDir;
        };
        home.file.".config/sandbox/sb.yaml".source = ./sb.yaml;

        # 共用 mise 目录就绪性标记：data/cache 子目录随激活创建（不破坏已有内容）
        home.activation.sandboxSharedMiseDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          mkdir -p "${sharedMiseDir}/data" "${sharedMiseDir}/cache"
        '';

        # 配置发布：在宿主把 live-edit 软链解引用成自包含副本，guest 才能读到
        # 发布目录路径固定，内容变化不改变上限指纹
        home.activation.sandboxPublishConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          run ${generator.publishScript}
        '';

        home.packages = [ sb ];
      };
    };
}
