# Agent 沙箱 Home Manager 特性装配入口 (Seam)
# 职责：
# 装配 SandboxConfig、SandboxGuest、SandboxHost 三个深模块，
# 声明 options 并挂载 activation 动作。
{
  flake.modules.homeManager.ai =
    {
      config,
      lib,
      mylib,
      pkgs,
      nixpkgs,
      ...
    }:
    let
      devTools = config.shelken.dev.tools;
      miseTools = config.shelken.dev.miseTools;
      writableRoots = config.shelken.dev.sandbox.writableRoots;
      # 本模块自己登记的宿主控制命令；computer-use、spawn-subagent、iphone 由各自模块登记，
      # guest 命令桩必须取合并后的 config.shelken.dev.sandbox.hostCommands
      selfHostCommands = {
        sb = "sb 是宿主沙箱管理 CLI，沙箱内部无法嵌套管理沙箱 VM";
        just = "just hm / just sw 是宿主系统切换命令，沙箱内无法修改宿主系统配置";
      };

      msbHome = "${config.home.homeDirectory}/Data/sandboxes/msb";
      cacheDir = "${config.home.homeDirectory}/.cache/microsandbox";
      sharedMiseDir = "${config.home.homeDirectory}/Data/sandboxes/mise/aarch64-linux";
      publishDir = "${config.home.homeDirectory}/.config/sandbox";

      gitConfig = (pkgs.formats.gitIni { }).generate "sandbox-git-config" {
        user = config.programs.git.settings.user;
        credential."https://github.com".helper = "!gh auth git-credential";
        url."https://github.com/".insteadOf = "git@github.com:";
      };

      # 1. 配置物化深模块 (SandboxConfig)：负责路径断言、声明文件收集与原子发布物化
      sandboxConfig = import ./_config.nix {
        inherit
          pkgs
          lib
          miseTools
          writableRoots
          publishDir
          ;
        tools = devTools;
      };

      # 2. Linux 执行隔离深模块 (SandboxGuest)：负责交叉编译、bwrap 容器隔离、sync 与 status 打包
      guest = import ./_guest.nix {
        inherit
          pkgs
          lib
          nixpkgs
          gitConfig
          ;
        inherit (config.shelken.dev.sandbox) hostCommands;
        tools = devTools;
      };

      # 3. 宿主驱动与 CLI 深模块 (SandboxHost)：负责接收原生 sb.yaml、VM 调度与 sb / omp-sb 打包
      host = import ./_host.nix {
        inherit pkgs msbHome cacheDir;
        policyFile = ./sb.yaml; # 原生 YAML 传入
        inherit (guest) launcher guestStatus;
      };

      # 闭合配置发布脚本：连接 config 与 guest 静态文件
      publishScript = sandboxConfig.mkPublishScript {
        inherit (guest) guestEnvSh syncGuestScript;
      };
    in
    {
      options.shelken.dev.ai.sandbox.enable =
        mylib.mkBoolOpt false "Whether to install the agent sandbox.";
      config = lib.mkIf config.shelken.dev.ai.sandbox.enable {
        inherit (sandboxConfig) assertions;

        shelken.dev.sandbox.hostCommands = selfHostCommands;
        programs.mise.globalConfig.tools.microsandbox = "0.7.7";

        home.sessionVariables = host.sessionVariables;
        home.file.".config/sandbox/sb.yaml".source = ./sb.yaml;

        # 共用 mise 目录就绪性标记：data 与 cache 子目录随激活创建（不破坏已有内容）
        home.activation.sandboxSharedMiseDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          mkdir -p "${sharedMiseDir}/data" "${sharedMiseDir}/cache"
        '';

        # 配置发布：在宿主把 live-edit 软链解引用成自包含副本，guest 才能读到
        # 发布目录路径固定，内容变化不改变上限指纹
        home.activation.sandboxPublishConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          run ${publishScript}
        '';

        home.packages = host.packages;
      };
    };
}
