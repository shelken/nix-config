{
  config,
  lib,
  pkgs,
  sources,
  ...
}:
let
  inherit (lib) mkIf mkOption types;
  cfg = config.shelken.dev.ai;

  skillsSourcePath = "${config.home.homeDirectory}/nix-config/home/base/gui/dev/ai/skills";

  # 外部 skill 统一交给 nvfetcher 固定来源和版本，避免 activation 阶段临时下载。
  fetchedSkillSources = {
    # anthropics/skills
    skill-creator = "${sources.anthropics-skills.src}/skills/skill-creator";

    # public-clis/bilibili-cli
    bilibili-cli = "${sources.bilibili-cli.src}/SKILL.md";
    twitter-cli = "${sources.twitter-cli.src}/SKILL.md";

    # FradSer/dotclaude
    best-practices = "${sources.dotclaude-skills.src}/refactor/skills/best-practices";
    refactor = "${sources.dotclaude-skills.src}/refactor/skills/refactor";
    refactor-project = "${sources.dotclaude-skills.src}/refactor/skills/refactor-project";

    # georgekhananaev/claude-skills-vault
    github-cli = "${sources.github-cli.src}/.claude/skills/github-cli";

    # JuliusBrussee/caveman
    caveman = "${sources.caveman.src}/skills/caveman";
    caveman-help = "${sources.caveman.src}/skills/caveman-help";

    # luoling8192/ai-coding-principles
    ai-coding-discipline = "${sources.ai-coding-principles.src}/ai-coding-discipline";
    ddia-principles = "${sources.ai-coding-principles.src}/ddia-principles";
    software-design-philosophy = "${sources.software-design-philosophy-skill.src}/SKILL.md";

    # microsoft/playwright-cli
    playwright-cli = "${sources.playwright-cli.src}/skills/playwright-cli";

    # MrGeDiao/shuorenhua
    shuorenhua = "${sources.shuorenhua.src}";

    # obra/superpowers
    brainstorming = "${sources.obra-superpowers.src}/skills/brainstorming";
    executing-plans = "${sources.obra-superpowers.src}/skills/executing-plans";
    subagent-driven-development = "${sources.obra-superpowers.src}/skills/subagent-driven-development";
    systematic-debugging = "${sources.obra-superpowers.src}/skills/systematic-debugging";
    test-driven-development = "${sources.obra-superpowers.src}/skills/test-driven-development";
    writing-plans = "${sources.obra-superpowers.src}/skills/writing-plans";
    writing-skills = "${sources.obra-superpowers.src}/skills/writing-skills";

    # onevcat/skills
    onevcat-jj = "${sources.onevcat-skills.src}/skills/onevcat-jj";

    # pbakaus/impeccable
    audit = "${sources.impeccable.src}/.claude/skills/audit";
    critique = "${sources.impeccable.src}/.claude/skills/critique";
    # harden = "${sources.impeccable.src}/.claude/skills/harden"; # 2.1.1 issue in codex: invalid YAML: mapping values are not allowed in this context at line 2 column 46
    impeccable = "${sources.impeccable.src}/.claude/skills/impeccable";
    optimize = "${sources.impeccable.src}/.claude/skills/optimize";
    polish = "${sources.impeccable.src}/.claude/skills/polish";

    # tw93/Waza
    health = "${sources.waza-skills.src}/skills/health";

    # upstash/context7
    context7-cli = "${sources.context7-cli.src}/skills/context7-cli";

    # vercel-labs/skills
    find-skills = "${sources.vercel-labs-skills.src}/skills/find-skills";
  };

  # 单文件来源统一包装成目录，skill 目标形态与目录来源保持一致，避免目录内再挂单文件链接。
  normalizeFetchedSkillSource =
    name: sourcePath:
    if lib.pathIsDirectory sourcePath then
      sourcePath
    else
      pkgs.writeTextDir (builtins.unsafeDiscardStringContext (builtins.baseNameOf (toString sourcePath))) (
        builtins.readFile sourcePath
      );

  fetchedSkillDirectories = lib.mapAttrs normalizeFetchedSkillSource fetchedSkillSources;

  localSkillDirs = builtins.attrNames (
    lib.filterAttrs (
      name: v: v == "directory" && !(builtins.elem name (builtins.attrNames fetchedSkillSources))
    ) (builtins.readDir ./skills)
  );

  localSkillSources = builtins.listToAttrs (
    map (name: {
      inherit name;
      value = config.lib.file.mkOutOfStoreSymlink "${skillsSourcePath}/${name}";
    }) localSkillDirs
  );

  localSkillLinks = lib.concatMap (
    targetPath:
    lib.mapAttrsToList (name: sourcePath: {
      name = "${targetPath}/${name}";
      value = {
        source = sourcePath;
        force = true;
      };
    }) localSkillSources
  ) cfg.skillTargets;

  fetchedSkillLinks = lib.concatMap (
    targetPath:
    lib.mapAttrsToList (name: sourcePath: {
      name = "${targetPath}/${name}";
      value = {
        source = sourcePath;
        force = true;
      };
    }) fetchedSkillDirectories
  ) cfg.skillTargets;

  allSkillLinks = lib.listToAttrs (localSkillLinks ++ fetchedSkillLinks);
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
  };

  config = mkIf cfg.enable {
    home.file = allSkillLinks;

    # 手动命令
    # npx skills update
    # npx skills add github/repo -g -y -a claude-code codex --skill [skill-name]
    # npx skills add microsoft/playwright-cli -g -y -a claude-code codex --skill playwright-cli
  };
}
