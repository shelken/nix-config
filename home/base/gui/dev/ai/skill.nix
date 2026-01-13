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
    lib.filterAttrs (name: type: type == "directory") (builtins.readDir ./skills)
  );

  # Generate skill symlinks for a single target path
  mkSkillLinks =
    targetPath:
    builtins.listToAttrs (
      map (name: {
        name = "${targetPath}/${name}";
        value = {
          source = config.lib.file.mkOutOfStoreSymlink "${skillsSourcePath}/${name}";
          force = true;
        };
      }) skillDirs
    );

  # Merge all target paths
  allSkillLinks = lib.foldl' (acc: path: acc // mkSkillLinks path) { } cfg.skillTargets;

  # Remote skills download script
  remoteSkillsScript = pkgs.writeShellScript "download-remote-skills" ''
    set -euo pipefail
    ${lib.concatMapStringsSep "\n" (skill: ''
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
      default = [ ".claude/skills" ];
      description = "Target directories for skill symlinks (relative to ~/)";
      example = [
        ".claude/skills"
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
        # 太烧token
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

    # Download remote skills on activation
    home.activation.downloadRemoteSkills = lib.mkIf (cfg.remoteSkills != [ ]) (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run ${remoteSkillsScript}
      ''
    );
  };
}
