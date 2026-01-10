{
  lib,
  mylib,
  config,
  ...
}:
let
  inherit (lib) mkIf;
  inherit (mylib) mkBoolOpt;
  cfg = config.shelken.dev.ai;
in
{
  options.shelken.dev.ai = {
    enable = mkBoolOpt false "Whether or not to enable.";
  };

  config = mkIf cfg.enable {
    homebrew = {
      brews = [
        # "ollama"
        # "gemini-cli"

        # "rust"
        # "ripgrep"
        "codex"
        "anomalyco/tap/opencode"
        # "kimi-cli"

        "max-sixty/worktrunk/wt" # 一个 Git Worktree 管理 CLI，旨在让 Worktree 的使用像分支一样简单。
      ];
      casks = [
        "ollama-app"
        "lm-studio"

        "claude-code"

        "alma"
        "osaurus"
      ];
    };
  };
}
