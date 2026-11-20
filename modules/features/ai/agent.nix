{ config, ... }:
{
  flake.modules.darwin.workstation.imports = [ config.flake.modules.darwin.ai ];

  flake.modules.homeManager.ai =
    {
      config,
      lib,
      mylib,
      pkgs,
      ...
    }:
    let
      cfg = config.shelken.dev.ai;

      agentsTargets = [
        {
          targetPath = ".claude";
          fileName = "CLAUDE.md";
        }
        {
          targetPath = ".gemini";
          fileName = "GEMINI.md";
        }
        {
          targetPath = ".codex";
          fileName = "AGENTS.md";
        }
        {
          targetPath = ".config/opencode";
          fileName = "AGENTS.md";
        }
        {
          targetPath = ".factory";
          fileName = "AGENTS.md";
        }
        {
          targetPath = ".pi/agent";
          fileName = "AGENTS.md";
        }
        {
          targetPath = ".omp/agent";
          fileName = "AGENTS.md";
        }
        {
          targetPath = ".dsh";
          fileName = "AGENTS.md";
        }
        {
          targetPath = ".config/zed";
          fileName = "AGENTS.md";
        }
        {
          targetPath = ".grok";
          fileName = "AGENTS.md";
        }
        {
          targetPath = ".workbuddy";
          fileName = "SOUL.md";
        }
      ];

      agentsLinks = builtins.listToAttrs (
        map (target: {
          name = "${target.targetPath}/${target.fileName}";
          value = mylib.mkConfigFile config ./_agents.md;
        }) agentsTargets
      );

      ownedBy = dir: lib.filterAttrs (name: _: lib.hasPrefix "${dir}/" name) agentsLinks;
    in
    {
      options.shelken.dev.ai.sandboxInstructions = lib.mkOption {
        type = lib.types.lines;
        default = "";
        description = ''
          追加在沙箱内 omp、pi 的 AGENTS.md 末尾的说明，宿主上的 AGENTS.md 不受影响。
          多个模块写入时按行合并；为空时沙箱沿用宿主同一份文件。
        '';
      };

      config = lib.mkMerge [
        {
          home.file = agentsLinks;
          shelken.dev.tools.omp.files = ownedBy ".omp";
          shelken.dev.tools.pi.files = ownedBy ".pi";
        }
        {
          shelken.dev.tools = lib.mkIf (cfg.sandboxInstructions != "") (
            let
              sandboxAgents = pkgs.writeText "AGENTS.sandbox.md" (
                builtins.readFile ./_agents.md + "\n" + cfg.sandboxInstructions
              );
            in
            {
              omp.sandboxFiles.".omp/agent/AGENTS.md" = sandboxAgents;
              pi.sandboxFiles.".pi/agent/AGENTS.md" = sandboxAgents;
            }
          );
        }
      ];
    };
}
