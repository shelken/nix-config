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
      # 软链仓库内文件，仓库中直接编辑即生效
      linkOmp = rel: mylib.mkConfigFile config (./. + "/${rel}");

      # 沙箱内 loopback 指向 VM 自身，模型地址统一改为宿主网关
      sandboxModels = (pkgs.formats.yaml { }).generate "omp-sandbox-models.yml" (
        mylib.rewriteLoopbackBaseUrls "host.microsandbox.internal" (mylib.readYaml pkgs ./models.yml)
      );

      # 沙箱专用插件清单：顶层 sandboxExclude 列出沙箱里不装的依赖。
      # 排除即不装，装什么完全由清单决定；宿主读原清单，不受影响。
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
        programs.zsh.initContent = ''
          # for mnemopi gemini embedding
          export MNEMOPI_EMBEDDING_DIM=3072
        '';
        # 别名：支持与 pi 并存，使用 sec-run omp
        home.shellAliases = {
          omp = "sec-run omp";
        };

        shelken.dev.sandbox.writableRoots = [ ".omp/agent" ];

        # omp 安装与插件补齐已迁入共享工具登记表（modules/features/ai/tools.nix 的 omp 条目）
        shelken.dev.tools.omp.sandboxFiles = {
          ".omp/agent/models.yml" = sandboxModels;
          # 沙箱版插件清单随发布目录进 guest，sb sync 的 postInstall 读它
          ".omp/agent/plugins-package.json" = sandboxManifest;
        };

        shelken.dev.tools.omp.files = {
          # omp 全局配置 / 快捷键 / 权限防护规则
          # 插件清单不在此列：它必须是普通副本，软链会被 omp plugin install 写穿到仓库
          ".omp/agent/config.yml" = linkOmp "config.yml";
          ".omp/agent/keybindings.yml" = linkOmp "keybindings.yml";
          ".omp/agent/permissions.yaml" = linkOmp "permissions.yaml";
          # 模型配置: provider 清单 + 自定义模型 (apiKey 为环境变量名, OMP resolveConfigValue 先查 env 后降级字面量)
          ".omp/agent/models.yml" = linkOmp "models.yml";
          ".omp/agent/context-prune/settings.json" =
            mylib.mkConfigFile config ../pi/configs/context-prune.json;
          # ".omp/agent/mcp.json" = linkOmp "mcp.json";
        }
        // extensionLinks;

        shelken.backup.app.omp = [
          "${config.home.homeDirectory}/.omp/agent/sessions"
        ];
      };
    };
}
