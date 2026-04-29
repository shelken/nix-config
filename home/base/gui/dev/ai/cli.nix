{
  lib,
  config,
  pkgs,
  sources,
  ...
}:
let
  # ctx7 不在 nixpkgs，使用 bunx wrapper 保持永远最新
  # bun 会缓存包，首次调用后不需要重复下载
  ctx7 = pkgs.writeShellScriptBin "ctx7" ''
    exec ${pkgs.bun}/bin/bunx ctx7@latest "$@"
  '';

  bili = pkgs.writeShellScriptBin "bili" ''
    exec ${pkgs.uv}/bin/uvx --from ${sources.bilibili-cli.src} bili "$@"
  '';

  twitter = pkgs.writeShellScriptBin "twitter" ''
    exec ${pkgs.uv}/bin/uvx --from ${sources.twitter-cli.src} twitter "$@"
  '';

  lit = pkgs.writeShellScriptBin "lit" ''
    exec ${pkgs.bun}/bin/bunx @llamaindex/liteparse "$@"
  '';
in
{
  config = lib.mkIf config.shelken.dev.ai.enable {
    programs.bun.enable = true;
    programs.gh.enable = true;
    programs.opencode = {
      enable = false; # use homebrew
    };

    home.packages = [
      ctx7
      bili
      twitter
      lit
      pkgs.imagemagick
    ];
  };
}
