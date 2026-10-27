{
  flake.modules.homeManager.ai =
    {
      config,
      lib,
      pkgs,
      mylib,
      sources,
      ...
    }:
    let
      inherit (lib) mkOption types;
      cfg = config.shelken.dev.ai;
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
      # 整树改写：漂移门需要跨 skill 的全局视野（同一专名可能出现在任意 skill），
      # 逐 skill 派生无法做这个断言。脚本幂等，每次 build 重算需要指针的集合。
      pstackSkills =
        pkgs.runCommand "pstack-skills"
          {
            nativeBuildInputs = [ pkgs.python3 ];
          }
          ''
            cp -r ${sources.cursor-plugins.src}/pstack $out
            chmod -R u+w $out
            python3 ${mylib.relativeToRoot "utils/script/adapt_pstack_skills.py"} \
              "$out" \
              ${./skills/pstack-harness/omp.md} \
              ${./skills/pstack-harness/pi.md}
          '';

      # home.file.source 不能是 "${派生}/子路径" 这类字符串：eval 期会做路径存在性检查而失败。
      # 每个 skill 单独成派生，链路与其它来源保持一致。
      pstackSkillSource =
        relativePath:
        pkgs.runCommand "pstack-skill-${flattenSkillName relativePath}" { } ''
          cp -r ${pstackSkills}/skills/${relativePath} $out
        '';

      fetchedSkillRepos = {
        anti-slop = {
          root = sources.anti-slop.src;
          skills.install-anti-slop = "skills/install-anti-slop";
          frontmatter.install-anti-slop.disable-model-invocation = true;
        };

        # ast-grep-agent-skill = {
        #   root = sources.ast-grep-agent-skill.src;
        #   skills.ast-grep = "ast-grep/skills/ast-grep";
        # };

        diagram-design = {
          root = sources.diagram-design.src;
          skills.diagram-design = "skills/diagram-design";
        };

        humanlayer-skills = {
          root = sources.humanlayer-skills.src;
          skills = {
            design-control-loop = "plugins/design-control-loop/skills/design-control-loop";
            show-me = "plugins/show-me/skills/show-me";
          };
          # skills.visual-pr = "plugins/visual-pr/skills/visual-pr";
        };

        llamaparse-agent-skills = {
          root = sources.llamaparse-agent-skills.src;
          skills.liteparse = "skills/liteparse";
        };

        mattpocock-skills = {
          root = sources.mattpocock-skills.src;
          skills = {
            improve-codebase-architecture = "skills/engineering/improve-codebase-architecture";
            codebase-design = "skills/engineering/codebase-design";
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
            implement-spec = "skills/engineering/implement-spec";
            setup-matt-pocock-skills = "skills/engineering/setup-matt-pocock-skills";
            wayfinder = "skills/engineering/wayfinder";
            research = "skills/engineering/research";
            domain-modeling = "skills/engineering/domain-modeling";
            ask-matt = "skills/engineering/ask-matt";
            triage = "skills/engineering/triage";
            retro = "skills/engineering/retro";
            pr = "skills/engineering/pr";
          };
        };

        pstack = {
          # 上游是 Cursor 方言：正文引用 Task/AskQuestion/~/.cursor/rules 等本机不存在的东西。
          # build 期插入指针并改写死链；discoverFrom 让 eval 扫上游源码，避免 IFD。
          root = pstackSkills;
          discoverFrom = "${sources.cursor-plugins.src}/pstack/skills";
          # 派生内的子目录不能直接当 source 字符串用，转成逐 skill 派生。
          resolveSource = pstackSkillSource;
          discover = true;
          exclude = [
            "tdd"
            "interrogate"
          ];
          frontmatter.poteto-mode.name = "poteto-mode";
          frontmatter.make-bot-ui.name = "make-bot-ui";
          frontmatter.setup-pstack.disable-model-invocation = true;
        };

        reverse-skill = {
          root = sources.reverse-skill.src;
          skills.reverse-skill = "skills";
        };

        security-audit-skill = {
          root = sources.security-audit-skill.src;
          skills.security-audit = "skills/security-audit";
          frontmatter.security-audit.disable-model-invocation = true;
        };
      };

      discoverSkillSources =
        repoName: scanRoot: resolve:
        listToAttrsWithUniqueNameCheck "${repoName}: 自动发现的 skill 名冲突。" (
          map (relativePath: {
            name = flattenSkillName relativePath;
            value = resolve relativePath;
          }) (collectSkillRootRelativePaths scanRoot "")
        );

      resolveSkillRepo =
        repoName: repo:
        let
          # 内容可能来自派生目录：eval 期只能扫上游源码，不能 readDir 尚未构建的产物（IFD）。
          scanRoot = repo.discoverFrom or repo.root;
          # 派生目录里的子路径不能当 source 字符串用（eval 会做存在性检查），由来源自行包装。
          resolve = repo.resolveSource or (relativePath: "${repo.root}/${relativePath}");
          discovered =
            if repo.discover or false then discoverSkillSources repoName scanRoot resolve else { };
          explicit = lib.mapAttrs (_: relativePath: resolve relativePath) (repo.skills or { });
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
            ${pkgs.python3}/bin/python ${mylib.relativeToRoot "utils/script/patch_frontmatter.py"} "$out/SKILL.md" \
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
