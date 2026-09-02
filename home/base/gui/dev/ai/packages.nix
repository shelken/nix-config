{
  lib,
  config,
  ...
}:
{
  # agent 相关 mise tools,由 dev.ai.enable 控制是否引入
  config = lib.mkIf config.shelken.dev.ai.enable {
    programs.mise.globalConfig.tools = {
      # agent tools
      herdr = "latest";
      worktrunk = "latest";
      rtk = "latest";
      "pipx:cua-cli" = "latest";
      "github:lycorp-jp/sim-use" = "latest";

      # agent client
      codex = "latest";
      claude-code = "latest";
      "npm:droid" = "latest";
      antigravity-cli = "latest";
      oh-my-pi = "latest";
    };
  };
}
