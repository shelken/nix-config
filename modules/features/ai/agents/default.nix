{
  flake.modules.homeManager.ai =
    {
      lib,
      pkgs,
      ...
    }:
    let
      # omp 与 pi 共用的 agent 定义：正文只有一份，模型只来自 config.yml 的角色，Nix 只写角色名。
      readOnlyOmpTools = "read, find, grep, glob, web_search";
      readOnlyPiTools = "read,grep,find,ls,ffgrep,fffind,web_search,web_fetch,intercom";

      # comment-sicko 只查本地代码与注释，严禁外网检索干扰
      commentSickoOmpTools = "read, find, grep, glob";
      commentSickoPiTools = "read,grep,find,ls,ffgrep,fffind,intercom";

      reviewerOmpTools = "read, find, grep, glob, bash, lsp, web_search, ast_grep";
      reviewerPiTools = "read,bash,grep,find,ls,ffgrep,fffind,web_search,web_fetch,intercom";

      workerOmpTools = "read, edit, write, bash, eval, todo, grep, find, glob, lsp, ast_grep, web_search";
      workerPiTools = "read,bash,edit,write,grep,find,ls,ffgrep,fffind,web_search,web_fetch,intercom";

      # judge 只裁决不改代码：给 web_search 查外部规范，不给 bash 防止偷偷改动代码。
      judgeOmpTools = "read, find, grep, glob, web_search";
      judgePiTools = "read,grep,find,ls,ffgrep,fffind,web_search,web_fetch,intercom";

      # omp 从 18.x 起自带这些 bundled agent，写进 agents 目录只是重复定义内置能力。
      ompBundledAgents = [
        "task"
        "scout"
        "sonic"
        "reviewer"
        "security-reviewer"
        "seance"
      ];

      # 变体声明：新增模型后缀只在 variants 加一行；新增支持变体的类别只在
      # variantCategories 加一行，其余生成逻辑自动生效。
      variants = [
        "gemini"
        "ds"
        "glm"
        "gpt"
        "cc"
        "agy"
      ];

      variantCategories = [
        "reviewer"
        "task"
      ];

      baseAgents = {
        task = {
          description = "General-purpose execution agent with full tool access; never use it for review, that is what the reviewers are for";
          variantDescription = "General-purpose execution agent with full tool access";
          ompTools = workerOmpTools;
          piTools = workerPiTools;
          body = ./prompts/task.md;
        };

        scout = {
          description = "Read-only codebase exploration and broad pattern search; returns compressed context another agent can act on";
          ompTools = readOnlyOmpTools;
          piTools = readOnlyPiTools;
          body = ./prompts/scout.md;
        };

        reviewer = {
          description = "Code review agent for quality, security, and correctness (read-only)";
          variantDescription = "Adversarial code reviewer (quality, security, correctness); read-only";
          ompTools = reviewerOmpTools;
          ompSpawns = "scout";
          # pi 的 profile 没有 spawns 概念，多派一个 reviewer-variant 才是它的跨家族面板。
          piTools = reviewerPiTools;
          body = ./prompts/reviewer.md;
          # output schema 只有 omp 认；挂在 agent 上，变体自动继承，无需按名字特判。
          extraFrontmatter = [ reviewerOutputSchema ];
        };

        judge = {
          description = "Adjudicator for arena candidates and plan options: scores against a rubric and names a base; never reviews a diff or edits code";
          ompTools = judgeOmpTools;
          piTools = judgePiTools;
          body = ./prompts/judge.md;
          # 裁决要的是强推理，不是审查模板；角色在 config.yml 里单列。
          modelRole = "judge";
        };

        poteto-agent = {
          description = "pstack poteto-mode execution agent: reads the poteto-mode skill first, then finishes the delegated task with full permissions";
          ompTools = workerOmpTools;
          ompSpawns = "*";
          piTools = workerPiTools;
          body = ./prompts/poteto-agent.md;
        };

        comment-sicko = {
          description = "Read-only comment reviewer: reports corpse comments, redundant narration, and workaround sermons; never edits product code";
          ompTools = commentSickoOmpTools;
          piTools = commentSickoPiTools;
          body = ./prompts/comment-sicko.md;
        };
      };

      # 类别 × 变体后缀的笛卡尔积：每个组合生成一个独立 agent，属性全部继承类别基础声明。
      generatedVariants = builtins.listToAttrs (
        lib.concatMap (
          cat:
          map (
            v:
            let
              base = baseAgents.${cat};
              name = "${cat}-${v}";
            in
            lib.nameValuePair name (
              lib.removeAttrs base [ "variantDescription" ]
              // {
                description = "${base.variantDescription or base.description} (model role ${name})";
              }
            )
          ) variants
        ) variantCategories
      );

      agentsCommon = baseAgents // generatedVariants;

      # ---------- 模型角色（omp 与 pi 共用）----------

      # Nix 只声明 agent 用哪个角色名；角色对应的模型只在运行时读 config.yml：
      # omp 解析 frontmatter 的 @role，pi 由 spawn-subagent 每次派发时读（见 docs/adr/0010）。
      # 变体的角色是静态规则：显式 modelRole > 生成的变体用 reviewer-<后缀> > 名字本身。
      # 新增 modelRoles 角色不会自动生效，需要在这里声明。
      roleOf =
        name:
        let
          a = agentsCommon.${name};
        in
        if a ? modelRole then
          a.modelRole
        else if generatedVariants ? ${name} then
          "reviewer-${lib.last (lib.splitString "-" name)}"
        else
          name;

      # pi 的 frontmatter 只有 description、role、tools 三个字段，description 与正文对每个 profile 都必须是独立文件。
      # 模型与 thinking 不写进 md：spawn-subagent 每次派发按 role 读 config.yml。
      # description 用 JSON 字符串输出（合法的 YAML 双引号串）：值里的 ": " 否则会让 YAML 解析失败。
      # role 是 roleOf 的结果，spawn-subagent 直接读它，不再自己推算角色。
      mkPiAgent = name: a: {
        name = "${name}.md";
        path = pkgs.writeText "${name}.md" (
          lib.concatStringsSep "\n" [
            "---"
            "description: ${builtins.toJSON a.description}"
            "role: ${roleOf name}"
            "tools: ${a.piTools}"
            "---"
            ""
            (builtins.readFile a.body)
          ]
          + "\n"
        );
      };

      # pi 没有内置 agent：每个 profile 都是独立 md，缺一个 spawn-subagent 就找不到它。
      piAgentsDir = pkgs.linkFarm "pi-agents" (lib.mapAttrsToList mkPiAgent agentsCommon);

      # ---------- omp ----------
      # 输出 omp 的 agent frontmatter；output schema 只有 omp 认，放在独立文件里按需附加。

      reviewerOutputSchema = lib.removeSuffix "\n" (builtins.readFile ./reviewer.output.yml);

      mkOmpAgent = name: a: {
        name = "${name}.md";
        path = pkgs.writeText "${name}.md" (
          lib.concatStringsSep "\n" (
            [
              "---"
              "name: ${name}"
              "description: ${a.description}"
              "tools: ${a.ompTools}"
            ]
            ++ lib.optional ((a.ompSpawns or null) != null) "spawns: ${a.ompSpawns}"
            ++ [ "model: @${roleOf name}" ]
            ++ (a.extraFrontmatter or [ ])
            ++ [
              "---"
              ""
              (builtins.readFile a.body)
            ]
          )
          + "\n"
        );
      };

      # -agy 走外部 agy CLI，由 spawn-subagent 派发；写进 omp agents 目录会被内置 task 工具当 HTTP provider 报错
      ompAgents = lib.filterAttrs (
        name: _: !(builtins.elem name ompBundledAgents) && !(lib.hasSuffix "-agy" name)
      ) agentsCommon;
      ompAgentsDir = pkgs.linkFarm "omp-agents" (lib.mapAttrsToList mkOmpAgent ompAgents);
    in
    {
      config = {
        shelken.dev.tools.omp.files.".omp/agent/agents".source = ompAgentsDir;
        shelken.dev.tools.pi.files.".pi/agent/agents" = {
          source = piAgentsDir;
          force = true;
        };
      };
    };
}
