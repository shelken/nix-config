# 外部 skill 来源的解析与部署。声明在 _skill-sources.nix（纯数据），这里把它解析成两件事：
#   - flake.skillSourceDirs：input → 启用的 skill 仓库内相对目录，CI 用它过滤 Renovate PR 的文件
#   - Home 的部署来源：分组/平铺规则与声明前一致
{ inputs, lib, ... }:
let
  declarations = import ./_skill-sources.nix;

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

  inputRoot = inputName: inputs.${inputName};

  # base 为 "." 时，skill 在 base 内的相对路径就是仓库内路径
  dirInRepo = base: relativePath: if base == "." then relativePath else "${base}/${relativePath}";

  # 一个分组 → 启用的 skill（名字 → base 内相对路径）及它们的仓库内目录。
  # discover 只扫 input 的源树，不读 build 期派生目录，避免 IFD。
  resolveGroup =
    groupName: decl:
    let
      base = decl.base;
      scanRoot = "${inputRoot decl.input}${if base == "." then "" else "/${base}"}";
      discovered =
        if decl.discover or false then
          listToAttrsWithUniqueNameCheck "${groupName}: 自动发现的 skill 名冲突。" (
            map (relativePath: {
              name = flattenSkillName relativePath;
              value = relativePath;
            }) (collectSkillRootRelativePaths scanRoot "")
          )
        else
          { };
      explicit = decl.skills or { };
      duplicateNames = lib.intersectLists (builtins.attrNames discovered) (builtins.attrNames explicit);
      combined = discovered // explicit;
      exclusions = decl.exclude or [ ];
      unknownExclusions = builtins.filter (name: !(builtins.hasAttr name combined)) exclusions;
      resolved = builtins.removeAttrs combined exclusions;
      overrideNames = builtins.attrNames (decl.frontmatter or { });
      unknownOverrides = builtins.filter (name: !(builtins.hasAttr name resolved)) overrideNames;
    in
    assert lib.assertMsg (
      duplicateNames == [ ]
    ) "${groupName}: 自动发现与显式声明存在同名 skill：${builtins.concatStringsSep ", " duplicateNames}";
    assert lib.assertMsg (
      unknownExclusions == [ ]
    ) "${groupName}: exclude 包含不存在的 skill：${builtins.concatStringsSep ", " unknownExclusions}";
    assert lib.assertMsg (
      unknownOverrides == [ ]
    ) "${groupName}: frontmatter 包含不存在的 skill：${builtins.concatStringsSep ", " unknownOverrides}";
    assert lib.assertMsg (resolved != { }) "${groupName}: 没有可用的 skill";
    {
      inherit (decl) input;
      frontmatter = decl.frontmatter or { };
      inherit base;
      derived = decl.derived or null;
      skills = resolved;
      dirs = lib.mapAttrs (_: relativePath: dirInRepo base relativePath) resolved;
    };

  groups = lib.mapAttrs resolveGroup declarations;

  skillSourceDirs = builtins.listToAttrs (
    map (inputName: {
      name = inputName;
      value = lib.sort builtins.lessThan (
        lib.unique (
          lib.concatMap (group: builtins.attrValues group.dirs) (
            lib.filter (group: group.input == inputName) (builtins.attrValues groups)
          )
        )
      );
    }) (lib.unique (map (group: group.input) (builtins.attrValues groups)))
  );
in
{
  # 供 CI 读取：某个 input 前进后，只看这些目录里的文件改动。
  # `nix eval --json .#skillSourceDirs` 只读 input 源树，不触发构建
  flake.skillSourceDirs = skillSourceDirs;

  flake.modules.homeManager.ai =
    {
      config,
      lib,
      pkgs,
      mylib,
      ...
    }:
    let
      inherit (lib) mkOption types;
      cfg = config.shelken.dev.ai;

      # 外部来源整树改写：漂移门需要跨 skill 的全局视野（同一专名可能出现在任意 skill），
      # 逐 skill 派生无法做这个断言。脚本幂等，每次 build 重算需要指针的集合。
      pstackSkills =
        pkgs.runCommand "pstack-skills"
          {
            nativeBuildInputs = [ pkgs.python3 ];
          }
          ''
            cp -r ${inputRoot groups.pstack.input}/${groups.pstack.derived} $out
            chmod -R u+w $out
            python3 ${mylib.relativeToRoot "utils/script/adapt_pstack_skills.py"} \
              "$out" \
              ${./skills/pstack-harness/omp.md} \
              ${./skills/pstack-harness/pi.md}
          '';

      # 普通分组取 input 源树里的目录；derived 分组的内容 build 期才生成，
      # 派生内的子目录不能当 source 字符串用（eval 会做存在性检查），逐 skill 复制成独立派生。
      groupSource =
        group: relativePath:
        let
          inRepo = dirInRepo group.base relativePath;
        in
        if group.derived == null then
          "${inputRoot group.input}/${inRepo}"
        else
          {
            derived = pkgs.runCommand "pstack-skill-${flattenSkillName relativePath}" { } ''
              cp -r ${pstackSkills}/${lib.removePrefix "${group.derived}/" inRepo} $out
            '';
          };

      fetchedSkillSourcesByRepo = lib.mapAttrs (
        _: group: lib.mapAttrs (_: groupSource group) group.skills
      ) groups;

      fetchedSkillRepos = lib.mapAttrs (_: group: { inherit (group) frontmatter; }) groups;

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
            ${pkgs.python3}/bin/python ${mylib.relativeToRoot "utils/script/patch_frontmatter.py"} "$out/SKILL.md" \
              ${lib.escapeShellArg (builtins.toJSON overrides)}
          '';

      normalizedFetchedSkillSourcesByRepo = lib.mapAttrs (
        repoName:
        lib.mapAttrs (
          skillName: sourcePath:
          let
            # 派生来源不经过单文件判定：pathIsDirectory/pathExists 会读派生产物，触发 IFD。
            resolvedSource = if builtins.isAttrs sourcePath then sourcePath.derived else sourcePath;
            normalized =
              if builtins.isAttrs sourcePath then resolvedSource else normalizeFetchedSkillSource sourcePath;
          in
          applyFrontmatterOverrides skillName normalized (
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

      mkLocalSkillSource = relativePath: mylib.mkConfigLink config (./skills + "/${relativePath}");

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
                  default = true;
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
            }
            {
              path = ".agents/skills"; # codex,opencode
            }
            {
              path = ".gemini/config/skills";
            }
            {
              path = ".workbuddy/skills";
            }
            {
              path = ".dsh/skills"; # dsh (deepseek-harness) 用户级 skills, 读取 $DSH_HOME/skills; dsh 不支持多目录结构, 必须展平
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
      config = {
        home.file = allSkillLinks;
        # skills 进共享工具登记表（与 agents 文档同机制）：宿主照常，沙箱经 files 拿到
        shelken.dev.tools.agent-common.package = null;
        shelken.dev.tools.agent-common.files = lib.filterAttrs (
          name: _: lib.hasPrefix ".agents/" name
        ) allSkillLinks;
        shelken.dev.sandbox.writableRoots = [ ".agents" ];

        # 手动命令
        # bunx skills update
        # bunx skills add github/repo -g -y -a claude-code codex --skill [skill-name]
        # bunx skills add microsoft/playwright-cli -g -y -a claude-code codex --skill playwright-cli
      };
    };
}
