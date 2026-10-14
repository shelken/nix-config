{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkIf;
  cfg = config.shelken.dev.ai;

  # 模型角色变体列表，对应 config.yml 中的 reviewer-* 角色
  reviewerVariants = [
    "general"
    "gemini"
    "ds"
    "glm"
    "gpt"
  ];

  template = builtins.readFile ./reviewer.template.md;

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
  agentsDir = pkgs.linkFarm "omp-agents" (generatedReviewers ++ extraAgents);
in
{
  config = mkIf cfg.enable {
    home.file.".omp/agent/agents".source = agentsDir;
  };
}
