{
  flake.modules.homeManager.ai =
    {
      ...
    }:
    {
      config = {
        programs.mise.globalConfig.tools = {
          # agent tools
          herdr = "latest";
          worktrunk = "0.79";
          rtk = "0.50";
          "pipx:cua-cli" = "0.1"; # computer-use 控制
          "github:lycorp-jp/sim-use" = "0.14"; # ios 模拟器控制

          # agent client
          # 需要保留的会定死版本
          # codex = "latest";
          # "npm:droid" = "latest";
          antigravity-cli = "1.1.24";
          codex = "0.160.1";
          claude-code = "2.1.304";
        };

        programs.zsh.initContent = ''
          # worktrunk (wt) shell integration
          if command -v wt >/dev/null 2>&1; then
            eval "$(wt config shell init zsh)"
          fi
        '';
      };
    };
}
