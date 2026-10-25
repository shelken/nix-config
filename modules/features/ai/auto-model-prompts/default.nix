{
  flake.modules.homeManager.ai =
    {
      config,
      lib,
      mylib,
      ...
    }:
    let
      # 软链仓库内文件，仓库中直接编辑即生效
      link = rel: mylib.mkConfigFile config (./. + "/${rel}");

      # matcher -> 仓库内源文件；matcher 由 pi-auto-model-prompts 按模型 ID 匹配，别名共用一个源
      matchers = {
        "cn-model" = "cn-model";
        "deepseek-v4*" = "deepseek-flash";
        "dfmodel" = "deepseek-flash";
        "gemini*" = "gemini";
        "glm*" = "glm";
        "gfmodel" = "glm";
        "gpt-5.6*" = "gpt-5.6";
        "gpt-6*" = "gpt-6";
        "grok*" = "grok";
        "mimo*" = "cn-model";
        "qwen*" = "cn-model";
      };

      promptLinks = lib.mapAttrs' (matcher: file: {
        name = ".agents/AGENTS.${matcher}.md";
        value = link "${file}.md";
      }) matchers;

      files = promptLinks // {
        # 插件配置与 prompt 同源，宿主无关（.pi / .omp 各读各的旧路径已废弃）
        ".agents/pi-auto-model-prompts/config.json" = link "config.json";
      };
    in
    {
      config = {
        home.file = files;
        # 进共享工具登记表：沙箱发布通道只认 shelken.dev.tools.<名>.files
        shelken.dev.tools.agent-common.package = null;
        shelken.dev.tools.agent-common.files = files;
      };
    };
}
