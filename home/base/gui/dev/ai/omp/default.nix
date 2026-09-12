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
        # omp 全局配置 / 快捷键 / 权限防护规则 / 插件清单
        ".omp/agent/config.yml" = linkOmp "config.yml";
        ".omp/agent/keybindings.yml" = linkOmp "keybindings.yml";
        ".omp/agent/permissions.yaml" = linkOmp "permissions.yaml";
        ".omp/plugins/package.json" = linkOmp "plugins/package.json";
      }
      // extensionLinks;

      # 自动化依赖安装：配置切换时静默确保 node_modules 就绪，无需手动敲命令
      home.activation.installOmpPlugins = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [ -f "$HOME/.omp/plugins/package.json" ]; then
          BUN="${pkgs.bun}/bin/bun"
          if command -v bun >/dev/null 2>&1; then
            BUN="$(command -v bun)"
          fi
          (cd "$HOME/.omp/plugins" && "$BUN" install --silent)
        fi
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
