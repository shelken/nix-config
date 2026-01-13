{
  config,
  lib,
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
in
{
  options.shelken.dev.ai.skillTargets = mkOption {
    type = types.listOf types.str;
    default = [ ".claude/skills" ];
    description = "Target directories for skill symlinks (relative to ~/)";
    example = [
      ".claude/skills"
      ".config/opencode/skills"
    ];
  };

  config = mkIf cfg.enable {
    home.file = allSkillLinks;
  };
}
