{
  flake.modules.homeManager.ai =
    {
      config,
      lib,
      mylib,
      ...
    }:
    let
      # 软链仓库内文件，仓库中直接编辑即生效
      linkOmp = rel: mylib.mkConfigFile config (./. + "/${rel}");

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
      config = {
        programs.zsh.initContent = ''
          # for mnemopi gemini embedding
          export MNEMOPI_EMBEDDING_DIM=3072
        '';
        # 别名：支持与 pi 并存，使用 sec-run omp
        home.shellAliases = {
          omp = "sec-run omp";
        };

        # omp 安装与插件补齐已迁入共享工具登记表（modules/features/ai/tools.nix 的 omp 条目）
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
