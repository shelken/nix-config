{
  flake.modules.homeManager.ai =
    {
      config,
      lib,
      mylib,
      pkgs,
      ...
    }:
    let
      linkOmp = rel: mylib.mkConfigFile config (./. + "/${rel}");

      ompManifest = builtins.fromJSON (builtins.readFile ./plugins/package.json);
      sandboxExclude = ompManifest.sandboxExclude or [ ];
      unknownExcludes = builtins.filter (n: !(ompManifest.dependencies ? ${n})) sandboxExclude;
      sandboxManifest =
        assert lib.assertMsg (
          unknownExcludes == [ ]
        ) "omp plugins/package.json 的 sandboxExclude 有 dependencies 里不存在的条目: ${toString unknownExcludes}";
        (pkgs.formats.json { }).generate "omp-sandbox-plugin-manifest.json" (
          builtins.removeAttrs ompManifest [ "sandboxExclude" ]
          // {
            dependencies = builtins.removeAttrs ompManifest.dependencies sandboxExclude;
          }
        );

      # 扩展目录内除 *.test.ts 外的 .ts 逐个软链；子目录整体软链（目录扩展的入口是 index.ts，
      # omp 只加载 index.ts，目录里的测试、文档不会被当成扩展）
      extensionEntries = builtins.attrNames (
        lib.filterAttrs (
          name: type:
          type == "directory"
          || (type == "regular" && lib.hasSuffix ".ts" name && !lib.hasSuffix ".test.ts" name)
        ) (builtins.readDir ./extensions)
      );
      extensionLinks = lib.listToAttrs (
        map (name: {
          name = ".omp/agent/extensions/${name}";
          value = linkOmp "extensions/${name}";
        }) extensionEntries
      );
    in
    {
      config = {
        shelken.dev.tools.omp.env.MNEMOPI_EMBEDDING_DIM = "3072";
        home.shellAliases.omp = "sec-run omp";

        shelken.dev.sandbox.writableRoots = [ ".omp/agent" ];

        shelken.dev.tools.omp.sandboxFiles = {
          ".omp/agent/plugins-package.json" = sandboxManifest;
        };

        shelken.dev.tools.omp.files = {
          # 插件清单不在此列：它必须是普通副本，软链会被 omp plugin install 写穿到仓库
          ".omp/agent/config.yml" = linkOmp "config.yml";
          ".omp/agent/keybindings.yml" = linkOmp "keybindings.yml";
          ".omp/agent/permissions.yaml" = linkOmp "permissions.yaml";
          # 模型配置: provider 清单 + 自定义模型 (apiKey 为环境变量名, OMP resolveConfigValue 先查 env 后降级字面量)
          ".omp/agent/models.yml" = linkOmp "models.yml";
          ".omp/agent/context-prune/settings.json" =
            mylib.mkConfigFile config ../pi/configs/context-prune.json;
        }
        // extensionLinks;

        shelken.backup.app.omp = [
          "${config.home.homeDirectory}/.omp/agent/sessions"
        ];
        shelken.sessionArchive.app.omp = [
          "${config.home.homeDirectory}/.omp/agent/sessions"
        ];
      };
    };
}
