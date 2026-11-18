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

      # omp 与 pi 的 models.yml 在构建期转 JSON 并合成 pi 的 models.json，Nix 求值期不读 YAML（ADR 0010）
      generatedModels =
        pkgs.runCommand "pi-models.json"
          {
            nativeBuildInputs = [
              pkgs.yj
              pkgs.jq
            ];
          }
          ''
            yj < ${../omp/models.yml} > omp-models.json
            yj < ${./models.yml} > pi-models.json
            jq -S -s -f ${./models.jq} omp-models.json pi-models.json > $out
          '';

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

    in
    {
      imports = [ ./_theme.nix ];

      # 插件读的环境变量写在登记表 env：宿主与沙箱同源（沙箱不继承宿主 shell 的环境）
      shelken.dev.tools.pi.env = {
        ANTIGRAVITY_NO_EXTRA_TOOLS = "1";
        # 关掉 pi-emphasis 自带的 ~1500 token 英文规则，改用 _agents.md 里的简版
        PI_EMPHASIS_GUIDANCE = "0";
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

        ".pi/agent/extensions/pi-rename.json" = linkPiConfig "pi-rename.json";
        ".pi/agent/extensions/pi-vision-handoff.json" = linkPiConfig "pi-vision-handoff.json";
        ".pi/agent/extensions/trae/config.json" = linkPiConfig "trae.json";
        # cpa 等 provider 的模型只来自 pi-dynamic-models 的自动发现，开关不在 Nix 里沙箱就拿不到
        ".pi/agent/extensions/pi-dynamic-models/config.json" = linkPiConfig "pi-dynamic-models.json";
        ".pi/agent/extensions/subdir-context.ts" =
          mylib.mkConfigFile config ../omp/extensions/subdir-context.ts;
        # guard 与 omp 共用一份源码，目录整体软链；pi 只加载目录内的 index.ts
        ".pi/agent/extensions/guard" = mylib.mkConfigFile config ../omp/extensions/guard;
        # omp 自带单行列截断，pi 没有；只有 pi 需要，不放进共享的 omp/extensions
        ".pi/agent/extensions/line-cap.ts" = linkPi "extensions/line-cap.ts";
      };

      shelken.backup.app.pi = [
        "${config.home.homeDirectory}/.pi/agent/sessions"
      ];
      shelken.sessionArchive.app.pi = [
        "${config.home.homeDirectory}/.pi/agent/sessions"
      ];
    };
}
