{
  config,
  lib,
  pkgs,
  mylib,
  system,
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
in
{
  config = mkIf cfg.enable {
    # 别名：支持与 pi 并存，使用 sec-run omp
    home.shellAliases = {
      omp = "sec-run omp";
    };

    programs.mise.globalConfig.tools.oh-my-pi = {
      version = "latest";
      minimum_release_age = "0h";
    };

    home.file = {
      # omp 全局配置 / 快捷键 / 权限防护规则
      # 插件清单不在此列：它必须是普通副本，软链会被 omp plugin install 写穿到仓库
      ".omp/agent/config.yml" = linkOmp "config.yml";
      ".omp/agent/keybindings.yml" = linkOmp "keybindings.yml";
      ".omp/agent/permissions.yaml" = linkOmp "permissions.yaml";
      # 模型配置: provider 清单 + 自定义模型 (apiKey 为环境变量名, OMP resolveConfigValue 先查 env 后降级字面量)
      ".omp/agent/models.yml" = linkOmp "models.yml";
      # ".omp/agent/mcp.json" = linkOmp "mcp.json";
    }
    // extensionLinks;

    # 插件目录以仓库清单为准：每次激活重放清单并重装，手装插件随之消失。
    # 清单用普通副本而非软链，否则 omp plugin install 会写穿到仓库文件；
    # bun install 不会移除多余包，所以 node_modules 直接删掉重建。
    home.activation.installOmpPlugins = lib.hm.dag.entryAfter [ "writeBoundary" "sops-nix" ] ''
      githubToken="$(${pkgs.gh}/bin/gh auth token)"
      plugins="$HOME/.omp/plugins"
      mkdir -p "$plugins"
      rm -rf "$plugins/node_modules" "$plugins/bun.lock" "$plugins/omp-plugins.lock.json" "$plugins/.bun-cache"
      cp -f ${./plugins/package.json} "$plugins/package.json"
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
