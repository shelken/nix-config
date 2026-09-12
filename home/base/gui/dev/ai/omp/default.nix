{
  config,
  lib,
  pkgs,
  system,
  ...
}:
let
  inherit (lib) mkIf;
  cfg = config.shelken.dev.ai;

  ompDir = "${config.home.homeDirectory}/nix-config/home/base/gui/dev/ai/omp";

  # 软链仓库内文件，仓库中直接编辑即生效
  linkOmp = rel: {
    source = config.lib.file.mkOutOfStoreSymlink "${ompDir}/${rel}";
    force = true;
  };

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
  config = mkIf cfg.enable (
    {
      # 别名：支持与 pi 并存，使用 sec-run omp
      home.shellAliases = {
        omp = "sec-run omp";
      };

      home.file = {
        # omp 全局配置 / 快捷键 / 权限防护规则
        # 插件清单不在此列：它必须是普通副本，软链会被 omp plugin install 写穿到仓库
        ".omp/agent/config.yml" = linkOmp "config.yml";
        ".omp/agent/keybindings.yml" = linkOmp "keybindings.yml";
        ".omp/agent/permissions.yaml" = linkOmp "permissions.yaml";
      }
      // extensionLinks;

      # 插件目录以仓库清单为准：每次激活重放清单并重装，手装插件随之消失。
      # 清单用普通副本而非软链，否则 omp plugin install 会写穿到仓库文件；
      # bun install 不会移除多余包，所以 node_modules 直接删掉重建。
      home.activation.installOmpPlugins = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        plugins="$HOME/.omp/plugins"
        mkdir -p "$plugins"
        rm -f "$plugins/package.json"
        cp -f ${lib.escapeShellArg "${ompDir}/plugins/package.json"} "$plugins/package.json"
        rm -rf "$plugins/node_modules" "$plugins/omp-plugins.lock.json"

        BUN="${pkgs.bun}/bin/bun"
        if command -v bun >/dev/null 2>&1; then
          BUN="$(command -v bun)"
        fi
        (cd "$plugins" && "$BUN" install --silent)
      '';

    }
    // lib.optionalAttrs (lib.hasSuffix "darwin" system) {
      # 备份 omp 数据目录
      shelken.backup.app.omp = [
        "${config.home.homeDirectory}/.omp"
      ];
    }
  );
}
