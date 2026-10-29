# Agent 沙箱 Home Manager 特性装配入口 (Seam)
# 职责：
# 汇集 SandboxManifest 规范，装配 SandboxConfig、SandboxGuest、SandboxHost 三个深模块，
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
      # 1. 唯一事实来源与静态断言 (SandboxManifest)
      manifest = import ./_manifest.nix { inherit config lib pkgs; };

      # 2. 配置物化深模块 (SandboxConfig)：负责声明文件收集与原子发布物化
      sandboxConfig = import ./_config.nix {
        inherit
          pkgs
          lib
          manifest
          ;
      };

      # 3. Linux 执行隔离深模块 (SandboxGuest)：负责交叉编译、bwrap 容器隔离、sync 与 status 打包
      guest = import ./_guest.nix {
        inherit
          pkgs
          lib
          nixpkgs
          manifest
          ;
      };

      # 4. 宿主驱动与 CLI 深模块 (SandboxHost)：负责接收原生 sb.yaml、VM 调度与 sb / omp-sb 打包
      host = import ./_host.nix {
        inherit
          pkgs
          manifest
          guest
          ;
        policyFile = ./sb.yaml; # 原生 YAML 传入
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
        inherit (manifest) assertions;

        shelken.dev.sandbox.hostCommands = manifest.hostCommands;
        programs.mise.globalConfig.tools.microsandbox = "0.7.7";

        home.sessionVariables = host.sessionVariables;
        home.file.".config/sandbox/sb.yaml".source = ./sb.yaml;

        # 共用 mise 目录就绪性标记：data 与 cache 子目录随激活创建（不破坏已有内容）
        home.activation.sandboxSharedMiseDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          mkdir -p "${manifest.statePaths.sharedMiseDir}/data" "${manifest.statePaths.sharedMiseDir}/cache"
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
