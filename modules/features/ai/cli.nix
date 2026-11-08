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
          # renovate: datasource=github-releases depName=rtk-ai/rtk extractVersion=^v(?<version>.+)$
          rtk = "1.2.0";
          # renovate: datasource=github-releases depName=lycorp-jp/sim-use
          "github:lycorp-jp/sim-use" = "0.14"; # ios 模拟器控制

          # agent client
          # 需要保留的会定死版本
          # "npm:droid" = "latest";
          # renovate: datasource=github-releases depName=google-antigravity/antigravity-cli
          antigravity-cli = "1.1.24";
          # 只在宿主用：不进共享登记表，沙箱里不装（沙箱只跑 omp、pi，见 ADR 0003）
          # renovate: datasource=github-releases depName=openai/codex extractVersion=^rust-v(?<version>.+)$
          codex = "0.160.1";
          # renovate: datasource=npm depName=@anthropic-ai/claude-code
          claude-code = "2.1.304";
        };
      };
    };
}
