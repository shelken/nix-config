{
  flake.modules.homeManager.ai =
    {
      config,
      lib,
      mylib,
      ...
    }:
    let
      link = rel: mylib.mkConfigFile config (./. + "/${rel}");

      matchers = {
        "cn-model" = "cn-model";
        "deepseek-v4*" = "deepseek-flash";
        "dfmodel" = "deepseek-flash";
        "gemini-3*" = "gemini-3";
        "gemini-4*" = "gemini-4";
        "glm*" = "glm";
        "gfmodel" = "glm";
        "gpt-5.6*" = "gpt-5.6";
        "gpt-6*" = "gpt-6";
        "mimo*" = "cn-model";
        "qwen*" = "cn-model";
      };

      promptLinks = lib.mapAttrs' (matcher: file: {
        name = ".agents/AGENTS.${matcher}.md";
        value = link "${file}.md";
      }) matchers;

      files = promptLinks // {
        ".agents/pi-auto-model-prompts/config.json" = link "config.json";
      };
    in
    {
      config = {
        home.file = files;
        shelken.dev.tools.agent-common.package = null;
        shelken.dev.tools.agent-common.files = files;
      };
    };
}
