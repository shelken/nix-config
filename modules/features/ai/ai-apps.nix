{ config, ... }:
{
  flake.modules.darwin.workstation.imports = [ config.flake.modules.darwin.ai-apps ];

  flake.modules.darwin.ai-apps.homebrew = {
    taps = [ ];
    casks = [

      "openusage"

      "alma"
    ];
  };

  flake.modules.homeManager.ai-apps.programs.mise.globalConfig.tools = {
    # renovate: datasource=github-releases depName=google-antigravity/antigravity-cli
    antigravity-cli = "1.5.9";
    # renovate: datasource=github-releases depName=openai/codex extractVersion=^rust-v(?<version>.+)$
    codex = "0.169.0";
    # renovate: datasource=npm depName=@anthropic-ai/claude-code
    claude-code = "2.1.325";
  };
}
