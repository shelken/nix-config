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

      # 沙箱专用 settings.json：顶层 sandboxExclude 列出沙箱里不要的 packages 条目。
      # 排除即不装，不是装后禁用；宿主读原文件，不受影响。
      # 名字写错在构建期失败，避免静默漏排除。对象形式的条目按 source 匹配，原样保留其余字段。
      # 匹配忽略 npm 条目的 @版本：升级版本时不用同步改 sandboxExclude。
      piSettings = builtins.fromJSON (builtins.readFile ./settings.json);
      sandboxExclude = map unversioned (piSettings.sandboxExclude or [ ]);
      unversioned =
        s:
        let
          m = builtins.match "(npm:@?[^@]+)(@.*)?" s;
        in
        if m == null then s else builtins.head m;
      entrySource = p: unversioned (if builtins.isString p then p else p.source);
      unknownExcludes = builtins.filter (
        n: !(builtins.any (p: entrySource p == n) piSettings.packages)
      ) sandboxExclude;
      sandboxSettings =
        assert lib.assertMsg (
          unknownExcludes == [ ]
        ) "pi settings.json 的 sandboxExclude 有 packages 里不存在的条目: ${toString unknownExcludes}";
        jsonFormat.generate "pi-settings-sandbox.json" (
          builtins.removeAttrs piSettings [ "sandboxExclude" ]
          // {
            packages = builtins.filter (p: !(builtins.elem (entrySource p) sandboxExclude)) piSettings.packages;
          }
        );

      # settings.json 声明的 npm 包名（去 npm: 前缀与 @版本）。`-npm:` 之类的禁用条目不计入
      npmDeclared = map (s: lib.removePrefix "npm:" s) (
        builtins.filter (lib.hasPrefix "npm:") (map entrySource piSettings.packages)
      );

      sandboxModels = jsonFormat.generate "pi-sandbox-models.json" {
        providers = mylib.rewriteLoopbackBaseUrls "host.microsandbox.internal" (
          lib.mapAttrs (_: adaptProvider) mergedModels.providers
        );
      };

    in
    {
      imports = [ ./_theme.nix ];

      home.packages = [ pkgs.mermaid-cli ];

      # 插件读的环境变量写在登记表 env：宿主与沙箱同源（沙箱不继承宿主 shell 的环境）
      shelken.dev.tools.pi.env = {
        ANTIGRAVITY_NO_EXTRA_TOOLS = "1";
        # @pify/shell-background：前台命令超过该毫秒数自动转后台（插件默认 30000）。
        # 对标 omp 的 bash.autoBackground 阈值（60 秒）；也可写 ~/.pi/agent/shell-background.json，这里选环境变量。
        PIFY_SHELL_BG_MS = "60000";
      };
      home.shellAliases.pi = "sec-run pi";

      shelken.dev.sandbox.writableRoots = [ ".pi/agent" ];

      # pi 只在 `pi install` / `pi remove` 时改 npm/package.json，启动时只补装缺失的包、从不清理；
      # settings.json 由本仓库声明，删掉一行 pi 并不知情，旧包会一直留在安装目录。
      # 这里按声明对账：多出来的包一次 `bun remove` 卸掉（与 pi remove 同一条命令，无需联网）。
      # 没有多余包时只花一次 jq；清理失败不阻断激活，下次再试。
      home.activation.piPruneNpm = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        npm_dir="${config.home.homeDirectory}/.pi/agent/npm"
        if [ -f "$npm_dir/package.json" ]; then
          stale=$(${pkgs.jq}/bin/jq -r --argjson keep '${builtins.toJSON npmDeclared}' \
            '(.dependencies // {}) | keys - $keep | .[]' "$npm_dir/package.json")
          if [ -n "$stale" ]; then
            run ${pkgs.bun}/bin/bun remove --cwd "$npm_dir" $stale \
              || warnEcho "pi npm 残留清理失败，下次激活重试"
          fi
        fi
      '';

      # pi 安装已迁入共享工具登记表（modules/features/ai/tools.nix 的 pi 条目）
      shelken.dev.tools.pi.sandboxFiles = {
        # 沙箱用 Nix 渲染的变体（去掉 sandboxExclude 列出的包）；宿主仍是仓库文件的软链
        ".pi/agent/settings.json" = sandboxSettings;
        ".pi/agent/models.json" = sandboxModels;
        # pi-caveman 在 XDG_CONFIG_HOME 有值时读 $XDG_CONFIG_HOME/pi/agent/caveman.json，不读 ~/.pi/agent；
        # 沙箱导出了 XDG_CONFIG_HOME，只挂 ~/.pi/agent 会让它回落默认值（full、显示状态栏）。
        ".config/pi/agent/caveman.json" = ./configs/caveman.json;
      };

      shelken.dev.tools.pi.files = {
        ".pi/agent/settings.json" = linkPi "settings.json";
        ".pi/agent/keybindings.json" = linkPi "keybindings.json";
        ".pi/agent/models.json" = {
          source = generatedModels;
          force = true;
        };
        ".pi/agent/permissions.yaml" = mylib.mkConfigFile config ../omp/permissions.yaml;
        # 整个目录软链：新增模板直接放进 prompts/，免改本文件
        ".pi/agent/prompts" = linkPi "prompts";

        ".pi/agent/caveman.json" = linkPiConfig "caveman.json";
        ".pi/agent/extensions/pi-recap.json" = linkPiConfig "pi-recap.json";
        ".pi/agent/extensions/pi-rename.json" = linkPiConfig "pi-rename.json";
        ".pi/agent/extensions/pi-vision-handoff.json" = linkPiConfig "pi-vision-handoff.json";
        ".pi/agent/extensions/trae/config.json" = linkPiConfig "trae.json";
        # cpa 等 provider 的模型只来自 pi-dynamic-models 的自动发现，开关不在 Nix 里沙箱就拿不到
        ".pi/agent/extensions/pi-dynamic-models/config.json" = linkPiConfig "pi-dynamic-models.json";
        ".pi/agent/extensions/subdir-context.ts" =
          mylib.mkConfigFile config ../omp/extensions/subdir-context.ts;
      };

      shelken.backup.app.pi = [
        "${config.home.homeDirectory}/.pi/agent/sessions"
      ];
    };
}
