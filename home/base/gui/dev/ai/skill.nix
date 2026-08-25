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

  flattenSkillName = lib.replaceStrings [ "/" ] [ "--" ];

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

  listToAttrsWithUniqueNameCheck =
    errorMsg: entries:
    let
      names = map (entry: entry.name) entries;
    in
    assert lib.assertMsg (builtins.length names == builtins.length (lib.unique names)) errorMsg;
    builtins.listToAttrs entries;

  # 外部来源只声明仓库根目录和选择策略，解析后统一进入现有分组/平铺流程。
  fetchedSkillRepos = {
    andrej-karpathy-skills = {
      root = sources.andrej-karpathy-skills.src;
      skills.karpathy-guidelines = "skills/karpathy-guidelines";
    };

    ast-grep-agent-skill = {
      root = sources.ast-grep-agent-skill.src;
      skills.ast-grep = "ast-grep/skills/ast-grep";
    };

    ai-coding-principles = {
      root = sources.ai-coding-principles.src;
      skills.ai-coding-discipline = "ai-coding-discipline";
    };

    humanlayer-skills = {
      root = sources.humanlayer-skills.src;
      skills.show-me = "plugins/show-me/skills/show-me";
    };

    llamaparse-agent-skills = {
      root = sources.llamaparse-agent-skills.src;
      skills.liteparse = "skills/liteparse";
    };

    mattpocock-skills = {
      root = sources.mattpocock-skills.src;
      skills = {
        improve-codebase-architecture = "skills/engineering/improve-codebase-architecture";
        diagnosing-bugs = "skills/engineering/diagnosing-bugs";
        grill-me = "skills/productivity/grill-me";
        grill-with-docs = "skills/engineering/grill-with-docs";
        grilling = "skills/productivity/grilling";
        handoff = "skills/productivity/handoff";
        prototype = "skills/engineering/prototype";
        tdd = "skills/engineering/tdd";
        to-tickets = "skills/engineering/to-tickets";
        to-spec = "skills/engineering/to-spec";
        writing-for-agents = "skills/productivity/writing-for-agents";
        loop-me = "skills/in-progress/loop-me";
        code-review = "skills/engineering/code-review";
        implement = "skills/engineering/implement";
        setup-matt-pocock-skills = "skills/engineering/setup-matt-pocock-skills";
        wayfinder = "skills/engineering/wayfinder";
        research = "skills/engineering/research";
        domain-modeling = "skills/engineering/domain-modeling";
        ask-matt = "skills/engineering/ask-matt";
        triage = "skills/engineering/triage";
      };
    };

    pstack = {
      root = "${sources.cursor-plugins.src}/pstack/skills";
      discover = true;
      exclude = [
        "tdd"
        "interrogate"
      ];
      frontmatter.poteto-mode.name = "poteto-mode";
      frontmatter.setup-pstack.disable-model-invocation = true;
    };

    reverse-skill = {
      root = sources.reverse-skill.src;
      skills.reverse-skill = "skills";
    };
  };

  discoverSkillSources =
    repoName: root:
    listToAttrsWithUniqueNameCheck "${repoName}: 自动发现的 skill 名冲突。" (
      map (relativePath: {
        name = flattenSkillName relativePath;
        value = "${root}/${relativePath}";
      }) (collectSkillRootRelativePaths root "")
    );

  resolveSkillRepo =
    repoName: repo:
    let
      discovered = if repo.discover or false then discoverSkillSources repoName repo.root else { };
      explicit = lib.mapAttrs (_: relativePath: "${repo.root}/${relativePath}") (repo.skills or { });
      duplicateNames = lib.intersectLists (builtins.attrNames discovered) (builtins.attrNames explicit);
      combined = discovered // explicit;
      exclusions = repo.exclude or [ ];
      unknownExclusions = builtins.filter (name: !(builtins.hasAttr name combined)) exclusions;
      resolved = builtins.removeAttrs combined exclusions;
      overrideNames = builtins.attrNames (repo.frontmatter or { });
      unknownOverrides = builtins.filter (name: !(builtins.hasAttr name resolved)) overrideNames;
    in
    assert lib.assertMsg (
      duplicateNames == [ ]
    ) "${repoName}: 自动发现与显式声明存在同名 skill：${builtins.concatStringsSep ", " duplicateNames}";
    assert lib.assertMsg (
      unknownExclusions == [ ]
    ) "${repoName}: exclude 包含不存在的 skill：${builtins.concatStringsSep ", " unknownExclusions}";
    assert lib.assertMsg (
      unknownOverrides == [ ]
    ) "${repoName}: frontmatter 包含不存在的 skill：${builtins.concatStringsSep ", " unknownOverrides}";
    assert lib.assertMsg (resolved != { }) "${repoName}: 没有可用的 skill";
    resolved;

  fetchedSkillSourcesByRepo = lib.mapAttrs resolveSkillRepo fetchedSkillRepos;

  # 单文件来源统一包装成目录，skill 目标形态与目录来源保持一致，避免目录内再挂单文件链接。
  normalizeFetchedSkillSource =
    sourcePath:
    if lib.pathIsDirectory sourcePath then
      sourcePath
    else
      pkgs.writeTextDir (builtins.unsafeDiscardStringContext (builtins.baseNameOf (toString sourcePath))) (
        builtins.readFile sourcePath
      );

  applyFrontmatterOverrides =
    skillName: sourcePath: overrides:
    if overrides == { } then
      sourcePath
    else
      pkgs.runCommand "skill-${skillName}" { } ''
        cp -r ${sourcePath} $out
        chmod -R +w $out
        ${pkgs.python3}/bin/python ${../../../../../utils/script/patch_frontmatter.py} "$out/SKILL.md" \
          ${lib.escapeShellArg (builtins.toJSON overrides)}
      '';

  normalizedFetchedSkillSourcesByRepo = lib.mapAttrs (
    repoName:
    lib.mapAttrs (
      skillName: sourcePath:
      applyFrontmatterOverrides skillName (normalizeFetchedSkillSource sourcePath) (
        fetchedSkillRepos.${repoName}.frontmatter.${skillName} or { }
      )
    )
  ) fetchedSkillSourcesByRepo;

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
        inherit (repo) name;
        value = mkFetchedRepoLinkFarm repo;
      };

  fetchedGroupedSkillEntries = map mkFetchedGroupedSkillEntry fetchedRepos;

  fetchedGroupedSkillSources = listToAttrsWithUniqueNameCheck "检测到外部 skill 分组命名冲突：请调整 skill 名，或启用平铺映射。" fetchedGroupedSkillEntries;

  fetchedFlattenSkillNames = builtins.attrNames fetchedFlattenSkillSources;

  localSkillEntries = builtins.readDir ./skills;

  isLocalGroupedSkill =
    name: fileType: fileType == "directory" && !(builtins.elem name fetchedFlattenSkillNames);

  localTopLevelSkillDirs = builtins.attrNames (lib.filterAttrs isLocalGroupedSkill localSkillEntries);

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
          path = ".agents/skills"; # codex,opencode
        }
        {
          path = ".gemini/config/skills";
          flatten = true;
        }
        {
          path = ".workbuddy/skills";
          flatten = true;
        }
        {
          path = ".dsh/skills"; # dsh (deepseek-harness) 用户级 skills, 读取 $DSH_HOME/skills; dsh 不支持多目录结构, 必须展平
          flatten = true;
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
    # bunx skills update
    # bunx skills add github/repo -g -y -a claude-code codex --skill [skill-name]
    # bunx skills add microsoft/playwright-cli -g -y -a claude-code codex --skill playwright-cli
  };
}
