{
  flake.modules.homeManager.ai =
    {
      pkgs,
      ...
    }:
    let
      # ctx7 不在 nixpkgs，使用 bunx wrapper 保持永远最新
      # bun 会缓存包，首次调用后不需要重复下载
      ctx7 = pkgs.writeShellScriptBin "ctx7" ''
        exec ${pkgs.bun}/bin/bunx ctx7@latest "$@"
      '';

      deepwiki = pkgs.writeShellScriptBin "deepwiki" ''
        exec ${pkgs.bun}/bin/bunx @seflless/deepwiki "$@"
      '';

      lit = pkgs.writeShellScriptBin "lit" ''
        exec ${pkgs.bun}/bin/bunx @llamaindex/liteparse "$@"
      '';

    in
    {
      config = {
        # bun/gh 由共享工具登记表提供（shelken.dev.tools，ADR 0003），不再各自 programs.* 声明
        programs.opencode = {
          enable = false; # use homebrew
        };

        home.packages = [
          ctx7
          deepwiki
          lit
          pkgs.agent-browser
          pkgs.ast-grep
          pkgs.imagemagick
        ];

        # 需要较新版本、用 mise 管理更方便的 CLI
        programs.mise.globalConfig.tools = {
          # agent tools
          herdr = "latest";
          worktrunk = "0.79";
          rtk = "0.50";
          "github:lycorp-jp/sim-use" = "0.14"; # ios 模拟器控制

          # agent client
          # 需要保留的会定死版本
          # codex = "latest";
          # "npm:droid" = "latest";
          antigravity-cli = "1.1.24";
          # codex / claude-code 已迁入共享工具登记表（modules/features/ai/tools.nix）
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
