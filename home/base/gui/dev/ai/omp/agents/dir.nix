{ pkgs, lib }:
let
  reviewerVariants = [
    "general"
    "gemini"
    "ds"
    "glm"
    "gpt"
  ];

  template = builtins.readFile ./reviewer.template.md;

  generatedReviewers = map (v: {
    name = "reviewer-${v}.md";
    path = pkgs.writeText "reviewer-${v}.md" (
      builtins.replaceStrings [ "@NAME@" "@MODEL@" ] [ "reviewer-${v}" "@reviewer-${v}" ] template
    );
  }) reviewerVariants;

  extraAgentFiles = builtins.attrNames (
    lib.filterAttrs (
      name: type: type == "regular" && lib.hasSuffix ".md" name && !lib.hasSuffix ".template.md" name
    ) (builtins.readDir ./.)
  );
  extraAgents = map (name: {
    inherit name;
    path = ./. + "/${name}";
  }) extraAgentFiles;
in
pkgs.linkFarm "omp-agents" (generatedReviewers ++ extraAgents)
