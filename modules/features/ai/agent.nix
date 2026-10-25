{
  flake.modules.homeManager.ai =
    {
      config,
      lib,
      mylib,
      ...
    }:
    let
      inherit (lib) mkOption types;
      cfg = config.shelken.dev.ai;

      # CLI tools and their agents file configurations
      # Format: { targetPath = "relative/path"; fileName = "FILENAME.md"; }
      defaultAgentsTargets = [
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
          fileName = "AGENTS.md"; # dsh (deepseek-harness) 用户全局指令, 读取 $DSH_HOME/AGENTS.md
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
          fileName = "SOUL.md"; # WorkBuddy 读取 ~/.workbuddy/SOUL.md 而非 AGENTS.md
        }
      ];

      # Generate symlinks for all agents targets
      agentsLinks = builtins.listToAttrs (
        map (target: {
          name = "${target.targetPath}/${target.fileName}";
          value = mylib.mkConfigFile config ./_agents.md;
        }) (if cfg.agentsTargets == [ ] then defaultAgentsTargets else cfg.agentsTargets)
      );

      # 沙箱只消费 omp 与 pi 的用户级配置（launcher 挂载 ~/.omp、~/.pi），其余是宿主独有工具
      ownedBy = dir: lib.filterAttrs (name: _: lib.hasPrefix "${dir}/" name) agentsLinks;
    in
    {
      options.shelken.dev.ai = {
        agentsTargets = mkOption {
          type = types.listOf (
            types.submodule {
              options = {
                targetPath = mkOption {
                  type = types.str;
                  description = "Target directory path relative to ~/";
                  example = ".claude";
                };
                fileName = mkOption {
                  type = types.str;
                  description = "Target file name for the agents document";
                  example = "CLAUDE.md";
                };
              };
            }
          );
          default = [ ];
          description = "List of target configurations for agents.md symlinks. Empty means use defaults.";
          example = [
            {
              targetPath = ".claude";
              fileName = "CLAUDE.md";
            }
            {
              targetPath = ".gemini";
              fileName = "GEMINI.md";
            }
          ];
        };

        claudePreset = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Claude preset";
        };
      };

      config = {
        home.file = agentsLinks;
        # agents 文档随所属工具登记（ADR 0003）：宿主照常作为 home.file，沙箱经该工具的 files 拿到同一份链接
        shelken.dev.tools.omp.files = ownedBy ".omp";
        shelken.dev.tools.pi.files = ownedBy ".pi";
      };
    };
}
