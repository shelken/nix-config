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
        programs.bun.enable = true;
        programs.gh.enable = true;
        programs.opencode = {
          enable = false; # use homebrew
        };

        # computer-use / spawn-subagent / iphone 与 skills 同源，软链到工作树源码即时生效
        home.file.".local/bin/computer-use" =
          mylib.mkConfigFile config ./skills/computer-use-best-practice/scripts/computer-use.ts;
        home.file.".local/bin/spawn-subagent" =
          mylib.mkConfigFile config ./skills/subagent-policy/spawn-subagent;
        home.file.".local/bin/iphone" =
          mylib.mkConfigFile config ./skills/iphone-use-best-practice/scripts/iphone;

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
