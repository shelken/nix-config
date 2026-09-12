{
  config,
  lib,
  ...
}:
let
  inherit (lib) mkIf;
  cfg = config.shelken.dev.ai;

  sourceDir = "${config.home.homeDirectory}/nix-config/home/base/gui/dev/ai/auto-model-prompts";

  # 软链仓库内文件，仓库中直接编辑即生效
  link = rel: {
    source = config.lib.file.mkOutOfStoreSymlink "${sourceDir}/${rel}";
    force = true;
  };

  # matcher -> 仓库内源文件；matcher 由 pi-auto-model-prompts 按模型 ID 匹配，别名共用一个源
  matchers = {
    "cn-model" = "cn-model";
    "deepseek-v4-flash" = "deepseek-flash";
    "deepseek-v4.1-flash" = "deepseek-flash";
    "gemini-*" = "gemini-*";
    "glm-*" = "glm-*";
    "gpt-5.5" = "gpt-5.5";
    "gpt-5.6-*" = "gpt-5.6-*";
    "grok*" = "grok*";
    "mimo*" = "cn-model";
    "qwen*" = "cn-model";
  };

  promptLinks = lib.mapAttrs' (matcher: file: {
    name = ".agents/AGENTS.${matcher}.md";
    value = link "${file}.md";
  }) matchers;
in
{
  config = mkIf cfg.enable {
    home.file = promptLinks // {
      # 插件配置与 prompt 同源，宿主无关（.pi / .omp 各读各的旧路径已废弃）
      ".agents/pi-auto-model-prompts/config.json" = link "config.json";
    };
  };
}
