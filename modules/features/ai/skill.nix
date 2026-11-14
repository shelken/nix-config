# skill 的唯一入口 shelken.dev.ai.skills（ADR 0009）：
#   - 选项挂在 core（ADR 0004「接口放 core」），任何功能都能声明自己需要的 skill
#   - 部署挂在 ai：链接到各 agent 的 skill 目录；ai 自己需要的通用 skill 也在这里声明
#   - flake.skillUpstreams：各主机 skill 的上游目录，CI 据此只展示在用目录的上游改动
{
  config,
  inputs,
  lib,
  ...
}:
{
  flake.modules.darwin.core.imports = [ config.flake.modules.darwin.skill-options ];
  flake.modules.nixos.core.imports = [ config.flake.modules.nixos.skill-options ];

  # 每台主机单独求值；读不到私有 secrets 的主机由 CI 脚本跳过
  flake.skillUpstreams = lib.mapAttrs (
    _: host:
    lib.unique (
      lib.concatMap (
        user:
        lib.filter (upstream: upstream != null) (map (skill: skill.upstream) user.shelken.dev.ai.skills)
      ) (lib.attrValues host.config.home-manager.users)
    )
  ) (config.flake.darwinConfigurations // config.flake.nixosConfigurations);

  flake.modules.homeManager.skill-options =
    { lib, ... }:
    let
      inherit (lib) mkOption types;
      sourceType = types.either types.path types.package;
      skillType = types.submodule (
        { config, ... }:
        {
          options = {
            source = mkOption {
              type = sourceType;
              description = "skill 目录：路径字面量（本仓库内，liveEdit 时软链回工作树）、input 里的目录字符串或派生";
            };
            name = mkOption {
              type = types.str;
              default =
                if lib.isDerivation config.source then
                  throw "shelken.dev.ai.skills：派生来源必须写 name"
                else
                  builtins.unsafeDiscardStringContext (baseNameOf (toString config.source));
              defaultText = lib.literalMD "`source` 的目录名";
              description = "skill 名，部署目录名";
            };
            frontmatter = mkOption {
              type = types.attrsOf types.anything;
              default = { };
              description = "覆盖 SKILL.md frontmatter 的字段";
            };
            upstream = mkOption {
              type = types.nullOr types.str;
              default = if builtins.isString config.source then config.source else null;
              defaultText = lib.literalMD "字符串来源时等于 `source`，否则为 `null`";
              description = "上游目录，CI 据此只展示在用目录的上游改动；派生来源需要手写";
            };
          };
        }
      );
    in
    {
      options.shelken.dev.ai.skills = mkOption {
        type = types.listOf (types.coercedTo sourceType (source: { inherit source; }) skillType);
        default = [ ];
        description = ''
          skill 列表。条目可以直接写来源，也可以写 { source; name; frontmatter; upstream; }；
          名字默认取来源的目录名，重名时求值失败。只在导入 ai 的主机上部署（ADR 0008）
        '';
      };
    };

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

      skillSource =
        skill:
        if skill.frontmatter != { } then
          # 逐字复制：与旧 applyFrontmatterOverrides 的构建脚本相同
          pkgs.runCommand "skill-${skill.name}" { } ''
            cp -r ${skill.source} $out
            chmod -R +w $out
            ${pkgs.python3}/bin/python ${mylib.relativeToRoot "utils/script/patch_frontmatter.py"} "$out/SKILL.md" \
              ${lib.escapeShellArg (builtins.toJSON skill.frontmatter)}
          ''
        else if builtins.isPath skill.source then
          mylib.mkConfigLink config skill.source
        else
          skill.source;

      # list 合并不查重：同名会让多个来源争同一个部署目录
      skillSources =
        let
          names = map (skill: skill.name) cfg.skills;
          duplicates = lib.unique (builtins.filter (name: lib.count (n: n == name) names > 1) names);
        in
        assert lib.assertMsg (duplicates == [ ]) "shelken.dev.ai.skills 有重名：${toString duplicates}";
        lib.listToAttrs (
          map (skill: {
            inherit (skill) name;
            value = skillSource skill;
          }) cfg.skills
        );

      allSkillLinks = lib.listToAttrs (
        lib.concatMap (
          target:
          lib.mapAttrsToList (name: source: {
            name = "${target}/${name}";
            value = {
              inherit source;
              force = true;
            };
          }) skillSources
        ) cfg.skillTargets
      );

      # 上游是 Cursor 方言：build 期整树改写（漂移门需要跨 skill 的全局视野），再逐个取出。逐字复制
      pstackSkills =
        pkgs.runCommand "pstack-skills"
          {
            nativeBuildInputs = [ pkgs.python3 ];
          }
          ''
            cp -r ${inputs.cursor-plugins}/pstack $out
            chmod -R u+w $out
            python3 ${mylib.relativeToRoot "utils/script/adapt_pstack_skills.py"} \
              "$out" \
              ${./skills/pstack-harness/omp.md} \
              ${./skills/pstack-harness/pi.md}
          '';

      # 从改写后的整树里取出单个 skill；子路径只是文本，丢掉字符串上下文，派生只依赖 pstackSkills
      pstackSkill =
        skill:
        skill
        // {
          source = pkgs.runCommand "pstack-skill-${skill.name}" { } ''
            cp -r ${pstackSkills}/${builtins.unsafeDiscardStringContext (lib.removePrefix "${inputs.cursor-plugins}/pstack/" skill.source)} $out
          '';
          upstream = skill.source;
        };

      # 本仓库自管
      local = mylib.discoverSkills ./skills { };

      # tdd 用 mattpocock 的版本
      pstack = map pstackSkill (
        mylib.discoverSkills "${inputs.cursor-plugins}/pstack/skills" {
          exclude = [ "tdd" ];
          frontmatter = {
            poteto-mode.name = "poteto-mode";
            make-bot-ui.name = "make-bot-ui";
            setup-pstack.disable-model-invocation = true;
          };
        }
      );

      mattpocock = map (dir: "${inputs.mattpocock-skills}/skills/${dir}") [
        "engineering/improve-codebase-architecture"
        "engineering/codebase-design"
        "engineering/diagnosing-bugs"
        "productivity/grill-me"
        "engineering/grill-with-docs"
        "productivity/grilling"
        "productivity/handoff"
        "engineering/prototype"
        "engineering/tdd"
        "engineering/to-tickets"
        "engineering/to-spec"
        "productivity/writing-for-agents"
        "in-progress/loop-me"
        # "engineering/code-review"
        "engineering/implement"
        "engineering/implement-spec"
        "engineering/setup-matt-pocock-skills"
        "engineering/wayfinder"
        "engineering/research"
        "engineering/domain-modeling"
        "engineering/ask-matt"
        "engineering/triage"
        "engineering/retro"
        "engineering/pr"
      ];

      humanlayer = [
        "${inputs.humanlayer-skills}/plugins/design-control-loop/skills/design-control-loop"
        {
          source = "${inputs.humanlayer-skills}/plugins/show-me/skills/show-me";
          frontmatter.disable-model-invocation = false;
        }
        # "${inputs.humanlayer-skills}/plugins/visual-pr/skills/visual-pr"
      ];

      # 只取一个 skill 的仓库
      singles = [
        "${inputs.caldo-skills}/skills/untangle-codebase"
        # pstack 把 CLI/TUI 验收委托给它；control-ui 由本机 agent-browser 承担，见 skills/pstack-harness
        "${inputs.cursor-plugins}/cursor-team-kit/skills/control-cli"
        "${inputs.diagram-design}/skills/diagram-design"
        "${inputs.llamaparse-agent-skills}/skills/liteparse"
        {
          source = "${inputs.anti-slop}/skills/install-anti-slop";
          frontmatter.disable-model-invocation = true;
        }
        {
          source = "${inputs.improve}/skills/improve";
          frontmatter.disable-model-invocation = true;
        }
        {
          source = "${inputs.security-audit-skill}/skills/security-audit";
          frontmatter.disable-model-invocation = true;
        }
      ];
    in
    {
      options.shelken.dev.ai.skillTargets = mkOption {
        type = types.listOf types.str;
        default = [
          ".claude/skills"
          ".agents/skills" # codex,opencode
          ".gemini/config/skills"
          ".workbuddy/skills"
          ".dsh/skills" # dsh (deepseek-harness) 用户级 skills, 读取 $DSH_HOME/skills; dsh 不支持多目录结构, 必须展平
        ];
        description = "skill 部署目标目录（相对 ~/）";
      };

      config = {
        shelken.dev.ai.skills = local ++ pstack ++ mattpocock ++ humanlayer ++ singles;

        home.file = allSkillLinks;
        # skills 进共享工具登记表（与 agents 文档同机制）：宿主照常，沙箱经 files 拿到
        shelken.dev.tools.agent-common.package = null;
        shelken.dev.tools.agent-common.files = lib.filterAttrs (
          name: _: lib.hasPrefix ".agents/" name
        ) allSkillLinks;
        shelken.dev.sandbox.writableRoots = [ ".agents" ];

        # skills CLI 由 mise 提供，版本钉死，不再用 npx/bunx 现取
        # renovate: datasource=npm depName=skills
        programs.mise.globalConfig.tools."npm:skills" = "1.8.1";

        # 手动命令
        # skills update
        # skills add github/repo -g -y -a claude-code codex --skill [skill-name]
        # skills add microsoft/playwright-cli -g -y -a claude-code codex --skill playwright-cli
      };
    };
}
