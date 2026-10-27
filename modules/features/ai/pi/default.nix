{
  flake.modules.homeManager.ai =
    {
      pkgs,
      config,
      lib,
      mylib,
      ...
    }:
    let
      linkPi = rel: mylib.mkConfigFile config (./. + "/${rel}");
      linkPiConfig = rel: mylib.mkConfigFile config (./configs + "/${rel}");
      jsonFormat = pkgs.formats.json { };
      readYaml = mylib.readYaml pkgs;

      sharedModels = readYaml ../omp/models.yml;
      piModels = readYaml ./models.yml;
      mergedModels = lib.recursiveUpdate sharedModels piModels;

      # omp thinking -> pi thinkingLevelMap 键位对齐 (pi 1.3.0 wire 序列化):
      #   reasoning ? effortMap[reasoning] ?? "high" : effortMap.off ?? void 0
      # - omp efforts[i]         -> pi <level> (compat.reasoningEffortMap 可改写档位;
      #     pi 会忽略该 compat 字段, 必须折进 map)
      # - omp defaultLevel       -> 不映射: pi 缺档时已回落 "high"
      # - omp requiresEffort:true -> pi off: <最低档>。off 置 null 时 pi 关思考不
      #     带 reasoning.effort, 强制思考模型 (cpa 全系) 400; 混合模型保持 null
      adaptModel =
        model:
        let
          thinking = model.thinking or null;
          efforts = if thinking == null then [ ] else thinking.efforts or [ ];
          effortMap = model.compat.reasoningEffortMap or { };
          requiresEffort = thinking != null && (thinking.requiresEffort or false);
          lowestEffort = builtins.head efforts;
        in
        builtins.removeAttrs model [ "thinking" ]
        // lib.optionalAttrs (efforts != [ ]) {
          thinkingLevelMap = {
            off = if requiresEffort then lowestEffort else null;
          }
          // lib.genAttrs efforts (level: effortMap.${level} or level);
        };

      adaptProvider =
        provider:
        let
          apiKey = provider.apiKey or null;
        in
        builtins.removeAttrs provider [ "discovery" ]
        // lib.optionalAttrs (provider ? apiKey && builtins.match "^[A-Z][A-Z0-9_]*$" apiKey != null) {
          apiKey = "${"$"}${apiKey}";
        }
        // lib.optionalAttrs (provider ? models) {
          models = map adaptModel provider.models;
        }
        // lib.optionalAttrs (provider ? modelOverrides) {
          modelOverrides = lib.mapAttrs (
            _: model:
            adaptModel (
              model
              // lib.optionalAttrs (provider ? compat) {
                compat = (provider.compat or { }) // (model.compat or { });
              }
            )
          ) provider.modelOverrides;
        };

      generatedModels = jsonFormat.generate "pi-models.json" {
        providers = lib.mapAttrs (_: adaptProvider) mergedModels.providers;
      };

      shellInit = ''
        export POWERLINE_NERD_FONTS=1
        export FFF_ENABLE_HOME_SCAN=0
      '';
    in
    {
      imports = [ ./_theme.nix ];

      home.packages = [ pkgs.mermaid-cli ];

      home.sessionVariables = {
        ANTIGRAVITY_NO_EXTRA_TOOLS = "1";
      };
      home.shellAliases.pi = "sec-run pi";

      shelken.dev.sandbox.writableRoots = [ ".pi/agent" ];

      # pi 安装已迁入共享工具登记表（modules/features/ai/tools.nix 的 pi 条目）
      shelken.dev.tools.pi.files = {
        ".pi/agent/settings.json" = linkPi "settings.json";
        ".pi/agent/keybindings.json" = linkPi "keybindings.json";
        ".pi/agent/models.json" = {
          source = generatedModels;
          force = true;
        };
        ".pi/agent/permissions.yaml" = mylib.mkConfigFile config ../omp/permissions.yaml;

        ".pi/agent/caveman.json" = linkPiConfig "caveman.json";
        ".pi/agent/context-prune/settings.json" = linkPiConfig "context-prune.json";
        ".pi/agent/extensions/pi-recap.json" = linkPiConfig "pi-recap.json";
        ".pi/agent/extensions/pi-rename.json" = linkPiConfig "pi-rename.json";
        ".pi/agent/extensions/pi-vision-handoff.json" = linkPiConfig "pi-vision-handoff.json";
        ".pi/agent/extensions/trae/config.json" = linkPiConfig "trae.json";
        # cpa 等 provider 的模型只来自 pi-dynamic-models 的自动发现，开关不在 Nix 里沙箱就拿不到
        ".pi/agent/extensions/pi-dynamic-models/config.json" = linkPiConfig "pi-dynamic-models.json";
        ".pi/agent/extensions/subdir-context.ts" =
          mylib.mkConfigFile config ../omp/extensions/subdir-context.ts;
      };

      programs.zsh.initContent = shellInit;

      shelken.backup.app.pi = [
        "${config.home.homeDirectory}/.pi/agent/sessions"
      ];
    };
}
