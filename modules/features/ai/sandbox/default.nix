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
      # 1. 纯净提取沙箱声明规范与前置校验（可写根合规、不嵌套、工具路径覆盖）
      spec = import ./_spec.nix { inherit config lib; };

      gitConfig = (pkgs.formats.gitIni { }).generate "sandbox-git-config" {
        user = spec.gitUser;
        credential."https://github.com".helper = "!gh auth git-credential";
        url."https://github.com/".insteadOf = "git@github.com:";
      };

      # 2. Linux guest 运行时抽象（工具闭包、环境变量统一规范、sync 逻辑、bubblewrap 隔离执行器）
      guest = import ./_guest.nix {
        inherit
          pkgs
          lib
          nixpkgs
          spec
          gitConfig
          ;
      };

      # 3. 声明配置物化与原子发布包（解引用 live-edit 外部软链、版本化发布目录、旧版本修剪）
      configBundle = import ./_config.nix {
        inherit
          pkgs
          lib
          spec
          guest
          ;
      };

      # 4. 宿主 VM 编排、策略与 CLI 打包（msb 配置注入、sb 与 omp-sb）
      runtime = import ./_runtime.nix {
        inherit
          pkgs
          spec
          guest
          ;
      };
    in
    {
      options.shelken.dev.ai.sandbox.enable =
        mylib.mkBoolOpt false "Whether to install the agent sandbox.";

      config = lib.mkIf config.shelken.dev.ai.sandbox.enable {
        inherit (spec) assertions;

        shelken.dev.sandbox.hostCommands = spec.hostCommands;
        programs.mise.globalConfig.tools.microsandbox = spec.microsandboxVersion;

        home.sessionVariables = {
          MSB_HOME = spec.paths.msbHome;
          MSB_CONFIG_PATH = "${runtime.msbConfig}";
        };
        home.file.".config/sandbox/sb.yaml".source = spec.policyFile;

        # 共用 mise 目录就绪性标记：data 与 cache 子目录随激活创建（不破坏已有内容）
        home.activation.sandboxSharedMiseDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          mkdir -p "${spec.paths.sharedMiseDir}/data" "${spec.paths.sharedMiseDir}/cache"
        '';

        # 配置发布：在宿主把 live-edit 软链解引用成自包含副本，guest 才能读到
        # 发布目录路径固定，内容变化不改变上限指纹
        home.activation.sandboxPublishConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          run ${configBundle.publishScript}
        '';

        home.packages = runtime.packages;
      };
    };
}
