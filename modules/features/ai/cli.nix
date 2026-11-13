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
          # renovate: datasource=github-releases depName=rtk-ai/rtk
          rtk = "1.2";
          # "github:lycorp-jp/sim-use" = "0.14"; # ios 模拟器控制(暂时不使用 使用iphone-use-best-practice)
        };
      };
    };
}
