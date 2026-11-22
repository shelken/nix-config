{
  flake.modules.homeManager.ai =
    {
      config,
      lib,
      mylib,
      pkgs,
      ...
    }:
    let
      readOnlyOmpTools = "read, find, grep, glob, web_search";
      readOnlyPiTools = "read,grep,find,ls,ffgrep,fffind,web_search,web_fetch,intercom";

      commentSickoOmpTools = "read, find, grep, glob";
      commentSickoPiTools = "read,grep,find,ls,ffgrep,fffind,intercom";

      reviewerOmpTools = "read, find, grep, glob, bash, lsp, web_search, ast_grep";
      reviewerPiTools = "read,bash,grep,find,ls,ffgrep,fffind,web_search,web_fetch,intercom";

      workerOmpTools = "read, edit, write, bash, eval, todo, grep, find, glob, lsp, ast_grep, web_search";
      workerPiTools = "read,bash,edit,write,grep,find,ls,ffgrep,fffind,web_search,web_fetch,intercom";

      judgeOmpTools = "read, find, grep, glob, web_search";
      judgePiTools = "read,grep,find,ls,ffgrep,fffind,web_search,web_fetch,intercom";

      ompBundledAgents = [
        "task"
        "scout"
        "sonic"
        "reviewer"
        "security-reviewer"
        "seance"
      ];

      variants = [
        "gemini"
        "ds"
        "glm"
        "gpt"
        "cc"
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
          piTools = reviewerPiTools;
          body = ./prompts/reviewer.md;
          extraFrontmatter = [ reviewerOutputSchema ];
        };

        judge = {
          description = "Adjudicator for arena candidates and plan options: scores against a rubric and names a base; never reviews a diff or edits code";
          ompTools = judgeOmpTools;
          piTools = judgePiTools;
          body = ./prompts/judge.md;
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
                modelRole = "reviewer-${v}";
              }
            )
          ) variants
        ) variantCategories
      );

      agentsCommon = baseAgents // generatedVariants;

      # description 用 JSON 字符串输出（合法的 YAML 双引号串）：值里的 ": " 否则会让 YAML 解析失败。
      mkPiAgent = name: a: {
        name = "${name}.md";
        path = pkgs.writeText "${name}.md" (
          lib.concatStringsSep "\n" [
            "---"
            "description: ${builtins.toJSON a.description}"
            "role: ${a.modelRole or name}"
            "tools: ${a.piTools}"
            "---"
            ""
            (builtins.readFile a.body)
          ]
          + "\n"
        );
      };

      piAgentsDir = pkgs.linkFarm "pi-agents" (lib.mapAttrsToList mkPiAgent agentsCommon);

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
            ++ [ "model: @${a.modelRole or name}" ]
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

        home.file.".local/bin/spawn-subagent" =
          mylib.mkConfigFile config ../skills/subagent-policy/spawn-subagent;

        home.file.".gemini/config/plugins/spawn-subagent" = mylib.mkConfigFile config ./agy-plugin;

        shelken.dev.sandbox.hostCommands.spawn-subagent =
          "spawn-subagent 在宿主终端 (Herdr/Kitty) 编排子代理，沙箱内无法访问宿主终端 multiplexer";
      };
    };
}
