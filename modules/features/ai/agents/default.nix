{
  flake.modules.homeManager.ai =
    {
      lib,
      pkgs,
      mylib,
      ...
    }:
    let
      # omp 与 pi 共用的 agent 定义：正文只有一份，模型只来自 config.yml 的角色。
      # omp 侧输出 frontmatter 头 + 正文；pi 侧额外解析 @role 成 provider/model + thinking。
      readOnlyOmpTools = "read, find, grep, glob";
      readOnlyPiTools = "read,grep,find,ls,ffgrep,fffind,intercom";

      reviewerOmpTools = "read, find, grep, glob, bash, lsp, web_search, ast_grep";
      reviewerPiTools = "read,bash,grep,find,ls,ffgrep,fffind,intercom";

      workerPiTools = "read,bash,edit,write,grep,find,ls,ffgrep,fffind,web_search,web_fetch,intercom";

      # judge 只裁决不改代码：不给 bash，读不到写不了的候选就没法被它偷偷改。
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

      reviewerVariants = [
        "general"
        "gemini"
        "ds"
        "glm"
        "gpt"
        "cc"
      ];

      reviewerDescription = "Adversarial code reviewer (quality, security, correctness); read-only";

      agentsCommon = {
        task = {
          description = "General-purpose execution agent with full tool access; never use it for review, that is what the reviewers are for";
          ompTools = "read, edit, write, bash, grep, find, glob, lsp, ast_grep, web_search";
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
          ompTools = reviewerOmpTools;
          ompSpawns = "scout";
          # pi 的 profile 没有 spawns 概念，多派一个 reviewer-variant 才是它的跨家族面板。
          piTools = reviewerPiTools;
          body = ./prompts/reviewer.md;
        };

        judge = {
          description = "Adjudicator for arena candidates and plan options: scores against a rubric and names a base; never reviews a diff or edits code";
          ompTools = readOnlyOmpTools;
          piTools = judgePiTools;
          body = ./prompts/judge.md;
          # 裁决要的是强推理，不是审查模板；角色在 config.yml 里单列。
          modelRole = "judge";
        };

        poteto-agent = {
          description = "pstack poteto-mode execution agent: reads the poteto-mode skill first, then finishes the delegated task with full permissions";
          ompTools = "read, edit, write, bash, grep, find, glob, lsp, ast_grep, web_search";
          ompSpawns = "*";
          piTools = workerPiTools;
          body = ./prompts/poteto-agent.md;
        };

        comment-sicko = {
          description = "Read-only comment reviewer: reports corpse comments, redundant narration, and workaround sermons; never edits product code";
          ompTools = readOnlyOmpTools;
          piTools = readOnlyPiTools;
          body = ./prompts/comment-sicko.md;
        };
      }
      // lib.genAttrs (map (v: "reviewer-${v}") reviewerVariants) (name: {
        description = "${reviewerDescription} (model role ${name})";
        ompTools = reviewerOmpTools;
        ompSpawns = "scout";
        piTools = reviewerPiTools;
        body = ./prompts/reviewer.md;
      });

      # ---------- 模型角色解析（omp 与 pi 共用）----------

      readYaml = mylib.readYaml pkgs;

      ompConfig = readYaml ../omp/config.yml;
      roles = ompConfig.modelRoles;
      agentModelOverrides = ompConfig.task.agentModelOverrides or { };

      # judge 不在 task.agentModelOverrides 里也能工作：它自己的 modelRoles 条目就是真相源。
      roleOf = name: agentsCommon.${name}.modelRole or name;
      modelOf = name: agentModelOverrides.${name} or "@${roleOf name}";

      # omp 与 pi 对同一服务的 provider 命名不同；映射与 spawn-subagent 热加载共用一份。
      piProviderAlias =
        (builtins.fromJSON (builtins.readFile ../skills/subagent-policy/subagent-config.json)).providerAlias
          or { };

      # "provider/model:level" 或 "@role[:level]" -> { model, thinking }；:level 覆盖被引用角色的 level
      parseSpec =
        spec:
        let
          m = builtins.match "(.*):(off|minimal|low|medium|high|xhigh|max)" spec;
        in
        if m == null then
          {
            ref = spec;
            level = null;
          }
        else
          {
            ref = builtins.elemAt m 0;
            level = builtins.elemAt m 1;
          };

      resolveSpec =
        spec:
        let
          p = parseSpec spec;
          base =
            if lib.hasPrefix "@" p.ref then
              resolveSpec roles.${lib.removePrefix "@" p.ref}
            else
              {
                model = p.ref;
                thinking = null;
              };
        in
        base // lib.optionalAttrs (p.level != null) { thinking = p.level; };

      toPiModel =
        model:
        let
          parts = lib.splitString "/" model;
        in
        lib.concatStringsSep "/" (
          [ (piProviderAlias.${builtins.head parts} or (builtins.head parts)) ] ++ builtins.tail parts
        );

      # pi 的 frontmatter 只有这四个字段；description 与正文对每个 profile 都必须是独立文件。
      mkPiAgent =
        name: a:
        let
          resolved = resolveSpec (modelOf name);
        in
        {
          name = "${name}.md";
          path = pkgs.writeText "${name}.md" (
            lib.concatStringsSep "\n" [
              "---"
              "description: ${a.description}"
              "model: ${toPiModel resolved.model}"
              "thinking: ${
                if resolved.thinking == null then
                  throw "agent ${name} 的模型角色未带 thinking 级别（config.yml 的 modelRoles）"
                else
                  resolved.thinking
              }"
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

      mkOmpAgent =
        name: a:
        let
          isReviewer = lib.hasPrefix "reviewer" name;
        in
        {
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
              ++ [ "model: ${modelOf name}" ]
              ++ lib.optional isReviewer reviewerOutputSchema
              ++ [
                "---"
                ""
                (builtins.readFile a.body)
              ]
            )
            + "\n"
          );
        };

      ompAgents = lib.filterAttrs (name: _: !(builtins.elem name ompBundledAgents)) agentsCommon;
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
