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
  # 结构：仓库分组 -> skill 名 -> skill 路径。
  fetchedSkillSourcesByRepo = {
    anthropics-skills = {
      skill-creator = "${sources.anthropics-skills.src}/skills/skill-creator";
    };

    andrej-karpathy-skills = {
      karpathy-guidelines = "${sources.andrej-karpathy-skills.src}/skills/karpathy-guidelines";
    };

    bilibili-cli = {
      bilibili-cli = "${sources.bilibili-cli.src}/SKILL.md";
    };

    twitter-cli = {
      twitter-cli = "${sources.twitter-cli.src}/SKILL.md";
    };

    dotclaude-skills = {
      best-practices = "${sources.dotclaude-skills.src}/refactor/skills/best-practices";
      refactor = "${sources.dotclaude-skills.src}/refactor/skills/refactor";
      refactor-project = "${sources.dotclaude-skills.src}/refactor/skills/refactor-project";
    };

    hindsight-skills = {
      hindsight-architect = "${sources.hindsight-skills.src}/skills/hindsight-architect";
      hindsight-docs = "${sources.hindsight-skills.src}/skills/hindsight-docs";
      hindsight-local = "${sources.hindsight-skills.src}/skills/hindsight-local";
    };

    caveman = {
      caveman = "${sources.caveman.src}/skills/caveman";
      caveman-help = "${sources.caveman.src}/skills/caveman-help";
    };

    ai-coding-principles = {
      ai-coding-discipline = "${sources.ai-coding-principles.src}/ai-coding-discipline";
      ddia-principles = "${sources.ai-coding-principles.src}/ddia-principles";
    };

    software-design-philosophy-skill = {
      software-design-philosophy = "${sources.software-design-philosophy-skill.src}/SKILL.md";
    };

    playwright-cli = {
      playwright-cli = "${sources.playwright-cli.src}/skills/playwright-cli";
    };

    shuorenhua = {
      shuorenhua = "${sources.shuorenhua.src}";
    };

    # sidkh-skills = {
    #   explain-code = "${sources.sidkh-skills.src}/explain-code";
    # };

    taste-skill = {
      industrial-brutalist-ui = "${sources.taste-skill.src}/skills/brutalist-skill";
      gpt-taste = "${sources.taste-skill.src}/skills/gpt-tasteskill";
      image-taste-frontend = "${sources.taste-skill.src}/skills/images-taste-skill";
      minimalist-ui = "${sources.taste-skill.src}/skills/minimalist-skill";
      full-output-enforcement = "${sources.taste-skill.src}/skills/output-skill";
      redesign-existing-projects = "${sources.taste-skill.src}/skills/redesign-skill";
      high-end-visual-design = "${sources.taste-skill.src}/skills/soft-skill";
      stitch-design-taste = "${sources.taste-skill.src}/skills/stitch-skill";
      design-taste-frontend = "${sources.taste-skill.src}/skills/taste-skill";
    };

    obra-superpowers = {
      brainstorming = "${sources.obra-superpowers.src}/skills/brainstorming";
      executing-plans = "${sources.obra-superpowers.src}/skills/executing-plans";
      subagent-driven-development = "${sources.obra-superpowers.src}/skills/subagent-driven-development";
      systematic-debugging = "${sources.obra-superpowers.src}/skills/systematic-debugging";
      test-driven-development = "${sources.obra-superpowers.src}/skills/test-driven-development";
      writing-plans = "${sources.obra-superpowers.src}/skills/writing-plans";
      writing-skills = "${sources.obra-superpowers.src}/skills/writing-skills";
    };

    impeccable = {
      impeccable = "${sources.impeccable.src}/.claude/skills/impeccable";
    };

    waza-skills = {
      health = "${sources.waza-skills.src}/skills/health";
    };

    vercel-labs-skills = {
      find-skills = "${sources.vercel-labs-skills.src}/skills/find-skills";
    };
  };

  # 单文件来源统一包装成目录，skill 目标形态与目录来源保持一致，避免目录内再挂单文件链接。
  normalizeFetchedSkillSource =
    sourcePath:
    if lib.pathIsDirectory sourcePath then
      sourcePath
    else
      pkgs.writeTextDir (builtins.unsafeDiscardStringContext (builtins.baseNameOf (toString sourcePath))) (
        builtins.readFile sourcePath
      );

  normalizeSkillSources = lib.mapAttrs (_: normalizeFetchedSkillSource);

  normalizedFetchedSkillSourcesByRepo = lib.mapAttrs (
    _: normalizeSkillSources
  ) fetchedSkillSourcesByRepo;

  listToAttrsWithUniqueNameCheck =
    errorMsg: entries:
    let
      names = map (entry: entry.name) entries;
      hasUniqueNames = builtins.length names == builtins.length (lib.unique names);
      _ = lib.assertMsg hasUniqueNames errorMsg;
    in
    builtins.listToAttrs entries;

  skillSourceToEntry = skillName: sourcePath: {
    name = skillName;
    value = sourcePath;
  };

  fetchedFlattenSkillEntries = lib.concatMap (
    skillSources: lib.mapAttrsToList skillSourceToEntry skillSources
  ) (builtins.attrValues normalizedFetchedSkillSourcesByRepo);

  fetchedFlattenSkillSources = listToAttrsWithUniqueNameCheck "检测到外部 skill 平铺命名冲突：请调整 skill 名，或改为非平铺映射。" fetchedFlattenSkillEntries;

  fetchedRepos = lib.mapAttrsToList (name: skillSources: {
    inherit name skillSources;
  }) normalizedFetchedSkillSourcesByRepo;

  mkFetchedRepoLinkFarm =
    repo:
    pkgs.linkFarm repo.name (
      lib.mapAttrsToList (skillName: sourcePath: {
        name = skillName;
        path = sourcePath;
      }) repo.skillSources
    );

  mkFetchedGroupedSkillEntry =
    repo:
    let
      skillNames = builtins.attrNames repo.skillSources;
      skillName = builtins.head skillNames;
    in
    if builtins.length skillNames == 1 then
      skillSourceToEntry skillName repo.skillSources.${skillName}
    else
      {
        name = repo.name;
        value = mkFetchedRepoLinkFarm repo;
      };

  fetchedGroupedSkillEntries = map mkFetchedGroupedSkillEntry fetchedRepos;

  fetchedGroupedSkillSources = listToAttrsWithUniqueNameCheck "检测到外部 skill 分组命名冲突：请调整 skill 名，或启用平铺映射。" fetchedGroupedSkillEntries;

  fetchedFlattenSkillNames = builtins.attrNames fetchedFlattenSkillSources;

  localSkillEntries = builtins.readDir ./skills;

  isLocalGroupedSkill =
    name: fileType: fileType == "directory" && !(builtins.elem name fetchedFlattenSkillNames);

  localTopLevelSkillDirs = builtins.attrNames (lib.filterAttrs isLocalGroupedSkill localSkillEntries);

  # pi 风格：遇到 SKILL.md 就把该目录当 skill 根，不继续向下。
  collectSkillRootRelativePaths =
    dirPath: relativePath:
    let
      entries = builtins.readDir dirPath;
      childDirs = builtins.attrNames (lib.filterAttrs (_: fileType: fileType == "directory") entries);
      childRelativePath =
        childName: if relativePath == "" then childName else "${relativePath}/${childName}";
    in
    if builtins.hasAttr "SKILL.md" entries then
      [ relativePath ]
    else
      lib.concatMap (
        childName: collectSkillRootRelativePaths "${dirPath}/${childName}" (childRelativePath childName)
      ) childDirs;

  flattenSkillName = relativePath: lib.replaceStrings [ "/" ] [ "--" ] relativePath;

  mkLocalSkillSource =
    relativePath: config.lib.file.mkOutOfStoreSymlink "${skillsSourcePath}/${relativePath}";

  localGroupedSkillSources = builtins.listToAttrs (
    map (name: {
      inherit name;
      value = mkLocalSkillSource name;
    }) localTopLevelSkillDirs
  );

  localFlattenSkillEntries = map (relativePath: {
    name = flattenSkillName relativePath;
    value = mkLocalSkillSource relativePath;
  }) (collectSkillRootRelativePaths ./skills "");

  localFlattenSkillSources = listToAttrsWithUniqueNameCheck "检测到本地 skill 平铺命名冲突：请调整目录名，或修改 flattenSkillName 规则。" localFlattenSkillEntries;

  localSkillSourcesFor =
    flatten: if flatten then localFlattenSkillSources else localGroupedSkillSources;
  fetchedSkillSourcesFor =
    flatten: if flatten then fetchedFlattenSkillSources else fetchedGroupedSkillSources;

  mkSkillLinks =
    targetPath: skillSources:
    lib.mapAttrsToList (name: sourcePath: {
      name = "${targetPath}/${name}";
      value = {
        source = sourcePath;
        force = true;
      };
    }) skillSources;

  linksForTarget =
    target:
    mkSkillLinks target.path (localSkillSourcesFor target.flatten)
    ++ mkSkillLinks target.path (fetchedSkillSourcesFor target.flatten);

  allSkillLinks = lib.listToAttrs (lib.concatMap linksForTarget cfg.skillTargets);
in
{
  options.shelken.dev.ai = {
    skillTargets = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            path = mkOption {
              type = types.str;
              description = "skill 目标目录（相对 ~/）";
            };

            flatten = mkOption {
              type = types.bool;
              default = false;
              description = ''
                是否平铺本地 skill。
                true: 递归查找含 SKILL.md 的目录并平铺（/ -> --）。
                false: 保留分组目录整体映射（pi 风格）。
              '';
            };
          };
        }
      );
      default = [
        {
          path = ".claude/skills";
          flatten = true;
        }
        {
          path = ".agents/skills"; # codex,opencode,gemini,antigravity
          flatten = false;
        }
      ];
      description = "skill 目标目录及映射策略";
      example = [
        {
          path = ".claude/skills";
          flatten = true;
        }
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
