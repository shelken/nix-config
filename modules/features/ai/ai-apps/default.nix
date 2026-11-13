# 只在工作站使用的 AI 桌面 App 与宿主专用的 agent 客户端
# 客户端不进共享工具登记表：沙箱只跑 omp、pi（ADR 0003）
{ config, ... }:
{
  flake.modules.darwin.workstation.imports = [ config.flake.modules.darwin.ai-apps ];

  flake.modules.darwin.ai-apps.homebrew = {
    taps = [ ];
    casks = [
      # "ollama-app"

      "openusage"

      "alma"
      # "osaurus"
    ];
  };

  flake.modules.homeManager.ai-apps.programs.mise.globalConfig.tools = {
    # 需要保留的会定死版本
    # "npm:droid" = "latest";
    # renovate: datasource=github-releases depName=google-antigravity/antigravity-cli
    antigravity-cli = "1.1.24";
    # renovate: datasource=github-releases depName=openai/codex extractVersion=^rust-v(?<version>.+)$
    codex = "0.160.1";
    # renovate: datasource=npm depName=@anthropic-ai/claude-code
    claude-code = "2.1.304";
  };
}
