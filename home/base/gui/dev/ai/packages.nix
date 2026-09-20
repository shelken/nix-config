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
      "pipx:cua-cli" = "latest"; # computer-use 控制
      "github:lycorp-jp/sim-use" = "latest"; # ios 模拟器控制
      "github:dmtrKovalenko/fff" = {
        # omp 使用
        version = "latest";
        matching = "fff-mcp";
        rename_exe = "fff-mcp";
      };

      # agent client
      # 需要保留的会定死版本
      # codex = "latest";
      # claude-code = "latest";
      # "npm:droid" = "latest";
      antigravity-cli = "1.1.24";
      oh-my-pi = "latest";
    };

    programs.zsh.initContent = ''
      # worktrunk (wt) shell integration
      if command -v wt >/dev/null 2>&1; then
        eval "$(wt config shell init zsh)"
      fi
    '';
  };
}
