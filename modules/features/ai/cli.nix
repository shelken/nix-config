{
  flake.modules.homeManager.ai =
    {
      lib,
      config,
      pkgs,
      mylib,
      ...
    }:
    let
      # ctx7 不在 nixpkgs，使用 bunx wrapper 保持永远最新
      # bun 会缓存包，首次调用后不需要重复下载
      ctx7 = pkgs.writeShellScriptBin "ctx7" ''
        exec ${pkgs.bun}/bin/bunx ctx7@latest "$@"
      '';

      # bili = pkgs.writeShellScriptBin "bili" ''
      #   exec ${pkgs.uv}/bin/uvx --from ${sources.bilibili-cli.src} bili "$@"
      # '';

      # twitter = pkgs.writeShellScriptBin "twitter" ''
      #   exec ${pkgs.uv}/bin/uvx --from ${sources.twitter-cli.src} twitter "$@"
      # '';

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

        # computer-use / spawn-subagent 与 skills 同源，软链到工作树源码即时生效
        home.file.".local/bin/computer-use" =
          mylib.mkConfigFile config ./skills/computer-use-best-practice/scripts/computer-use.ts;
        home.file.".local/bin/spawn-subagent" =
          mylib.mkConfigFile config ./skills/subagent-policy/spawn-subagent;

        shelken.dev.sandbox.hostCommands = {
          computer-use = "computer-use 控制宿主 macOS 图形界面，沙箱内无法访问宿主窗口";
          spawn-subagent = "spawn-subagent 在宿主终端 (Herdr/Kitty) 编排子代理，沙箱内无法访问宿主终端 multiplexer";
        };

        home.packages = [
          ctx7
          deepwiki
          lit
          pkgs.agent-browser
          pkgs.ast-grep
          # bil
          # twitter
          pkgs.imagemagick
        ];
      };
    };
}
