{
  config,
  lib,
  pkgs,
  mylib,
  ...
}:
let
  inherit (lib) mkIf;
  cfg = config.shelken.dev.ai;

  # 软链仓库内文件，仓库中直接编辑即生效
  linkOmp = rel: mylib.mkConfigFile config "home/base/gui/dev/ai/omp/${rel}";

  # 扩展目录内除 *.test.ts 外的 .ts 逐个软链；目录内还含测试与 AGENTS.md，不能整目录软链
  extensionFiles = builtins.attrNames (
    lib.filterAttrs (
      name: type: type == "regular" && lib.hasSuffix ".ts" name && !lib.hasSuffix ".test.ts" name
    ) (builtins.readDir ./extensions)
  );
  extensionLinks = lib.listToAttrs (
    map (name: {
      name = ".omp/agent/extensions/${name}";
      value = linkOmp "extensions/${name}";
    }) extensionFiles
  );

  microsandboxModels =
    pkgs.runCommand "omp-models-microsandbox.yml"
      {
        nativeBuildInputs = [ pkgs.yq-go ];
      }
      ''
        yq '(.. | select(tag == "!!map") | select(has("baseUrl")) | .baseUrl) |= sub("^(https?://)(127[.]0[.]0[.]1|localhost|\\[::1\\])([:/]|$)", "''${1}host.microsandbox.internal''${3}")' ${./models.yml} > "$out"
      '';

  # 基础配置文件映射，消除重复
  baseConfigFiles = {
    "config.yml" = linkOmp "config.yml";
    "keybindings.yml" = linkOmp "keybindings.yml";
    "permissions.yaml" = linkOmp "permissions.yaml";
    "models.yml" = linkOmp "models.yml";
    "context-prune/settings.json" =
      mylib.mkConfigFile config "home/base/gui/dev/ai/pi/configs/context-prune.json";
  };

  # ADR 0007: 声明式聚合沙箱纯配置集，单次整树挂载消除散装枚举与清单漂移
  sandboxConfig = pkgs.linkFarm "omp-sandbox-config" (
    [
      {
        name = "config.yml";
        path = baseConfigFiles."config.yml".source;
      }
      {
        name = "keybindings.yml";
        path = baseConfigFiles."keybindings.yml".source;
      }
      {
        name = "permissions.yaml";
        path = baseConfigFiles."permissions.yaml".source;
      }
      {
        name = "models.yml";
        path = microsandboxModels;
      }
      {
        name = "AGENTS.md";
        path = mylib.mkConfigLink config "home/base/gui/dev/ai/_agents.md";
      }
      {
        name = "context-prune/settings.json";
        path = baseConfigFiles."context-prune/settings.json".source;
      }
      {
        name = "plugins/package.json";
        path = ./plugins/package.json;
      }
      {
        name = "agents";
        path = config.home.file.".omp/agent/agents".source;
      }
    ]
    ++ (map (name: {
      name = "extensions/${name}";
      path = mylib.mkConfigLink config "home/base/gui/dev/ai/omp/extensions/${name}";
    }) extensionFiles)
  );
in
{
  imports = [ ./agents ];

  config = mkIf cfg.enable {
    programs.zsh.initContent = ''
      # for mnemopi gemini embedding
      export MNEMOPI_EMBEDDING_DIM=3072
    '';
    # 别名：支持与 pi 并存，使用 sec-run omp
    home.shellAliases = {
      omp = "sec-run omp";
    };

    programs.mise.globalConfig.tools.oh-my-pi = {
      version = "latest";
      minimum_release_age = "0h";
    };

    home.file =
      (lib.mapAttrs' (name: val: lib.nameValuePair ".omp/agent/${name}" val) baseConfigFiles)
      // extensionLinks
      // {
        # 暴露单一纯配置目录供沙箱单次整树挂载（ADR 0007）
        ".omp/sandbox-config".source = sandboxConfig;
      };

    # 插件目录以仓库清单为准：每次激活重放清单并重装，手装插件随之消失。
    # 清单用普通副本而非软链，否则 omp plugin install 会写穿到仓库文件；
    # 但 store 里的源文件是只读的，cp 在目标不存在时会连权限一起继承（444），
    # 导致 bun install 报 EACCES，故复制后必须显式补可写位。
    # bun install 不会移除多余包，所以 node_modules 直接删掉重建。
    home.activation.installOmpPlugins = lib.hm.dag.entryAfter [ "writeBoundary" "sops-nix" ] ''
      githubToken="$(${pkgs.gh}/bin/gh auth token)"
      plugins="$HOME/.omp/plugins"
      mkdir -p "$plugins"
      rm -rf "$plugins/node_modules" "$plugins/bun.lock" "$plugins/omp-plugins.lock.json" "$plugins/.bun-cache"
      cp -f ${./plugins/package.json} "$plugins/package.json"
      chmod u+w "$plugins/package.json"
      # Bun 对 #main 分支依赖的解析结果会命中多层内部缓存（上游缺陷 #11548，1.4.2 未修复），
      # 给本次安装一个一次性缓存目录强制全新解析，全局 ~/.bun/install/cache 原样保留
      PATH="${pkgs.git}/bin:$PATH" GITHUB_TOKEN="$githubToken" BUN_INSTALL_CACHE_DIR="$plugins/.bun-cache" \
        ${pkgs.bun}/bin/bun install --cwd "$plugins" --silent
      unset githubToken
    '';

    shelken.backup.app.omp = [
      "${config.home.homeDirectory}/.omp/agent/sessions"
    ];
  };
}
