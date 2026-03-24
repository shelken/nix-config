{
  config,
  lib,
  pkgs,
  mylib,
  ...
}:
let
  inherit (lib) mkIf mkOption types;
  cfg = config.shelken.dev.ai;

  skillsSourcePath = "${config.home.homeDirectory}/nix-config/home/base/gui/dev/ai/skills";

  skillDirs = builtins.attrNames (
    lib.filterAttrs (_: v: v == "directory") (builtins.readDir ./skills)
  );

  allSkillLinks = lib.listToAttrs (
    lib.concatMap (
      targetPath:
      map (name: {
        name = "${targetPath}/${name}";
        value = {
          source = config.lib.file.mkOutOfStoreSymlink "${skillsSourcePath}/${name}";
          force = true;
        };
      }) skillDirs
    ) cfg.skillTargets
  );

  remoteSkillsScript = pkgs.writeShellScript "download-remote-skills" ''
    set -euo pipefail
    ${lib.concatMapStrings (skill: ''
      mkdir -p "${skillsSourcePath}/${skill.name}"
      echo "Downloading skill: ${skill.name}"
      ${pkgs.curl}/bin/curl -fsSL -o "${skillsSourcePath}/${skill.name}/${skill.fileName}" "${skill.url}"
    '') cfg.remoteSkills}
  '';
in
{
  options.shelken.dev.ai = {
    skillTargets = mkOption {
      type = types.listOf types.str;
      default = [
        ".claude/skills"
        ".agents/skills" # codex,opencode,gemini,antigravity
      ];
      description = "Target directories for skill symlinks (relative to ~/)";
      example = [
        ".claude/skills"
        ".gemini/antigravity/skills"
        ".config/opencode/skills"
      ];
    };

    remoteSkills = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            name = mkOption {
              type = types.str;
              description = "Skill directory name";
              example = "agent-browser";
            };
            fileName = mkOption {
              type = types.str;
              default = "SKILL.md";
              description = "Target file name";
            };
            url = mkOption {
              type = types.str;
              description = "URL to fetch the skill file from";
              example = "https://raw.githubusercontent.com/vercel-labs/agent-browser/main/skills/agent-browser/SKILL.md";
            };
          };
        }
      );
      default = [
        # 优先持久化到skills目录下而不是remote
        # {
        #   name = "agent-browser";
        #   url = "https://raw.githubusercontent.com/vercel-labs/agent-browser/main/skills/agent-browser/SKILL.md";
        # }
      ];
      description = "Remote skills to download on each switch";
    };
  };

  config = mkIf cfg.enable {
    home.file = allSkillLinks;

    # 手动命令
    # npx skills update
    # npx skills add github/repo -g -y -a claude-code codex --skill [skill-name]
    # npx skills add obra/superpowers -g -y -a claude-code codex --skill brainstorming systematic-debugging writing-plans test-driven-development executing-plans subagent-driven-development writing-skills
    # npx skills add microsoft/playwright-cli -g -y -a claude-code codex --skill playwright-cli
    # npx skills add pbakaus/impeccable -g -y -a claude-code codex --skill audit critique extract harden normalize onboard optimize teach-impeccable

    # Download remote skills on activation
    home.activation.downloadRemoteSkills = lib.mkIf (cfg.remoteSkills != [ ]) (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run ${remoteSkillsScript}
      ''
    );
  };
}
