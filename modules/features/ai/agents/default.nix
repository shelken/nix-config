{
  flake.modules.homeManager.ai =
    {
      lib,
      pkgs,
      mylib,
      ...
    }:
    let
      # 模型角色变体列表，对应 omp/config.yml 中的 reviewer-* 角色；omp 与 pi 共用
      reviewerVariants = [
        "general"
        "gemini"
        "ds"
        "glm"
        "gpt"
        "cc"
      ];

      # pstack 工作流的自定义 agent：omp 与 pi 共用 prompts/ 下的正文，
      # 模型统一取自 config.yml 的 task.agentModelOverrides，两端改一处即同步。
      customAgents = {
        poteto-agent = {
          description = "pstack poteto-mode 执行代理：先读 poteto-mode skill，再全权限完成被委派的任务";
          tools = "read, edit, write, bash, grep, find, glob, lsp, ast_grep, web_search";
          piTools = "read,bash,edit,write,grep,find,ls,ffgrep,fffind,web_search,web_fetch,intercom";
          spawns = "*";
          body = ./prompts/poteto-agent.md;
        };
        comment-sicko = {
          description = "只读注释审查员：只报尸体注释、冗余叙述与 workaround 说教，绝不改业务代码";
          tools = "read, find, grep, glob";
          piTools = "read,grep,find,ls,ffgrep,fffind,intercom";
          spawns = null;
          body = ./prompts/comment-sicko.md;
        };
      };

      # ---------- omp ----------

      template = builtins.readFile ./reviewer.template.md;

      customModel =
        name:
        agentModelOverrides.${name}
          or (throw "agent ${name} 的模型角色未在 config.yml 的 task.agentModelOverrides 中声明");

      mkOmpAgent = name: a: {
        name = "${name}.md";
        path = pkgs.writeText "${name}.md" (
          lib.concatStringsSep "\n" (
            [
              "---"
              "name: ${name}"
              "description: ${a.description}"
              "tools: ${a.tools}"
            ]
            ++ lib.optional (a.spawns != null) "spawns: ${a.spawns}"
            ++ [
              "model: ${customModel name}"
              "---"
              ""
              (builtins.readFile a.body)
            ]
          )
          + "\n"
        );
      };

      generatedCustom = map (name: mkOmpAgent name customAgents.${name}) (
        builtins.attrNames customAgents
      );

      # 为每个 reviewer 变体生成带有独立 name 与 model 的 .md 文件
      generatedReviewers = map (v: {
        name = "reviewer-${v}.md";
        path = pkgs.writeText "reviewer-${v}.md" (
          builtins.replaceStrings [ "@NAME@" "@MODEL@" ] [ "reviewer-${v}" "@reviewer-${v}" ] template
        );
      }) reviewerVariants;

      # 扫描 agents 目录下除了 *.template.md 和 *.nix 之外的其他普通 .md 文件（支持手写自定义 agent）
      extraAgentFiles = builtins.attrNames (
        lib.filterAttrs (
          name: type: type == "regular" && lib.hasSuffix ".md" name && !lib.hasSuffix ".template.md" name
        ) (builtins.readDir ./.)
      );
      extraAgents = map (name: {
        inherit name;
        path = ./. + "/${name}";
      }) extraAgentFiles;

      # 聚合所有 agents 并构建软链目录
      ompAgentsDir = pkgs.linkFarm "omp-agents" (generatedReviewers ++ generatedCustom ++ extraAgents);

      # ---------- pi ----------
      # pi 的 agent 与 omp 内置/自定义 agent 同名，模型与 thinking 取自 omp/config.yml，
      # 保证两边改一处角色配置即同步；spawn-subagent 以这里生成的 md 为真相源。

      readYaml = mylib.readYaml pkgs;

      ompConfig = readYaml ../omp/config.yml;
      roles = ompConfig.modelRoles;
      agentModelOverrides = ompConfig.task.agentModelOverrides or { };

      # omp 与 pi 对同一服务的 provider 命名不同
      piProviderAlias = {
        google-antigravity = "antigravity";
      };

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

      readOnlyTools = "read,grep,find,ls,ffgrep,fffind,web_search,web_fetch,intercom";
      reviewTools = "read,bash,grep,find,ls,ffgrep,fffind,intercom";

      piAgents = {
        task = {
          description = "通用执行代理，完全工具权限，专注完成被委派的任务（勿用于 review，用 reviewer 系列）";
          tools = "read,bash,edit,write,grep,find,ls,ffgrep,fffind,web_search,web_fetch,intercom";
          body = ./prompts/task.md;
        };
        scout = {
          description = "只读代码库探索，快速分析与广泛模式搜索，返回可交接的压缩上下文";
          tools = readOnlyTools;
          body = ./prompts/scout.md;
        };
        reviewer = {
          description = "代码审查代理，检查质量、安全与正确性（只读）";
          tools = reviewTools;
          body = null;
        };
      }
      // lib.genAttrs (builtins.attrNames customAgents) (name: {
        description = customAgents.${name}.description;
        tools = customAgents.${name}.piTools;
        body = customAgents.${name}.body;
      })
      // lib.genAttrs (map (v: "reviewer-${v}") reviewerVariants) (name: {
        description = "对抗性代码审查员（模型角色 ${name}）";
        tools = reviewTools;
        body = null;
      });

      mkPiAgent =
        name: a:
        let
          resolved = resolveSpec (agentModelOverrides.${name} or "@${name}");
        in
        {
          name = "${name}.md";
          path = pkgs.writeText "${name}.md" (
            lib.concatStringsSep "\n" (
              [
                "---"
                "description: ${a.description}"
                "model: ${toPiModel resolved.model}"
                "thinking: ${
                  if resolved.thinking == null then
                    throw "agent ${name} 的模型角色未带 thinking 级别（config.yml 的 modelRoles）"
                  else
                    resolved.thinking
                }"
                "tools: ${a.tools}"
                "---"
              ]
              ++ lib.optional (a.body != null) ("\n" + builtins.readFile a.body)
            )
            + "\n"
          );
        };

      piAgentsDir = pkgs.linkFarm "pi-agents" (lib.mapAttrsToList mkPiAgent piAgents);
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
