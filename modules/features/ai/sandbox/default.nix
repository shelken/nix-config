{
  flake.modules.homeManager.ai =
    {
      config,
      lib,
      mylib,
      myvars,
      pkgs,
      inputs,
      ...
    }:
    let
      manifest = import ./_manifest.nix { inherit config lib; };

      guest = import ./_guest.nix {
        inherit (inputs) nixpkgs;
        inherit
          pkgs
          lib
          manifest
          ;
        agentOwner = myvars.username;
      };

      sandboxConfig = import ./_config.nix {
        inherit
          pkgs
          lib
          manifest
          guest
          ;
      };

      host = import ./_host.nix {
        inherit
          pkgs
          lib
          manifest
          guest
          ;
        policyFile = ./sb.yaml;
        # 用户本人的 GitHub token 不经 sec-run 进入宿主环境，由 sb 在创建、启动 VM 时直接读 sops 文件
        hostSecretFiles = lib.optionalAttrs config.shelken.secrets.enable {
          GITHUB_TOKEN = config.sops.secrets."github/cli-token".path;
        };
      };
    in
    {
      options.shelken.dev.ai.sandbox.enable =
        mylib.mkBoolOpt false "Whether to install the agent sandbox.";

      config = lib.mkIf config.shelken.dev.ai.sandbox.enable {
        inherit (manifest) assertions;

        shelken.dev.sandbox.hostCommands = {
          sb = "sb 是宿主沙箱管理 CLI，沙箱内部无法嵌套管理沙箱 VM";
          just = "just hm / just sw 是宿主系统切换命令，沙箱内无法修改宿主系统配置";
        };
        # renovate: datasource=github-releases depName=superradcompany/microsandbox
        programs.mise.globalConfig.tools.microsandbox = "0.7.15";

        home.sessionVariables = host.sessionVariables;

        home.activation.sandboxSharedMiseDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          mkdir -p "${manifest.miseLayer.hostDir}/${manifest.miseLayer.dataSub}" "${manifest.miseLayer.hostDir}/${manifest.miseLayer.cacheSub}"
        '';

        # guest 读不到宿主上 live-edit 的软链，所以发布成自包含副本；发布目录路径固定，内容变化不改变上限指纹
        home.activation.sandboxPublishConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          run ${sandboxConfig.publishScript}
        '';

        home.packages = host.packages;
      };
    };
}
