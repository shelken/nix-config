{
  lib,
  config,
  pkgs,
  ...
}:
let
  # ctx7 不在 nixpkgs，使用 bunx wrapper 保持永远最新
  # bun 会缓存包，首次调用后不需要重复下载
  ctx7 = pkgs.writeShellScriptBin "ctx7" ''
    exec ${pkgs.bun}/bin/bunx ctx7@latest "$@"
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
    ];
  };
}
