{
  config,
  lib,
  mylib,
  ...
}:
let
  inherit (lib) mkIf mkOption types;
  cfg = config.shelken.dev.ai;

  agentsSourcePath = "${config.home.homeDirectory}/nix-config/home/base/gui/dev/ai/_agents.md";

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
  ];

  # Generate symlinks for all agents targets
  agentsLinks = builtins.listToAttrs (
    map (target: {
      name = "${target.targetPath}/${target.fileName}";
      value = {
        source = config.lib.file.mkOutOfStoreSymlink agentsSourcePath;
        force = true;
      };
    }) (if cfg.agentsTargets == [ ] then defaultAgentsTargets else cfg.agentsTargets)
  );
in
{
  options.shelken.dev.ai.agentsTargets = mkOption {
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

  config = mkIf cfg.enable {
    home.file = agentsLinks;
  };
}
