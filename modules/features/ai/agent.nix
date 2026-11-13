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
      cfg = config.shelken.dev.ai;

      # CLI tools and their agents file configurations
      # Format: { targetPath = "relative/path"; fileName = "FILENAME.md"; }
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
        }) agentsTargets
      );

      # 沙箱只消费 omp 与 pi 的用户级配置（launcher 挂载 ~/.omp、~/.pi），其余是宿主独有工具
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
          # agents 文档随所属工具登记（ADR 0003）：宿主照常作为 home.file，沙箱经该工具的 files 拿到同一份链接
          shelken.dev.tools.omp.files = ownedBy ".omp";
          shelken.dev.tools.pi.files = ownedBy ".pi";
        }
        {
          # 沙箱拿到的本来就是发布副本，生成新文件不损失 liveEdit
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
