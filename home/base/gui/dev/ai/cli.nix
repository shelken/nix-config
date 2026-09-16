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

  # bili = pkgs.writeShellScriptBin "bili" ''
  #   exec ${pkgs.uv}/bin/uvx --from ${sources.bilibili-cli.src} bili "$@"
  # '';

  # twitter = pkgs.writeShellScriptBin "twitter" ''
  #   exec ${pkgs.uv}/bin/uvx --from ${sources.twitter-cli.src} twitter "$@"
  # '';

  lit = pkgs.writeShellScriptBin "lit" ''
    exec ${pkgs.bun}/bin/bunx @llamaindex/liteparse "$@"
  '';

  # 软链到工作树源码：改脚本即时生效，无需 rebuild。
  # 路径用字符串拼接而不是 ${./…} 插值，插值会把文件复制进 store。
  skillsDir = "${config.home.homeDirectory}/nix-config/home/base/gui/dev/ai/skills";
in
{
  config = lib.mkIf config.shelken.dev.ai.enable {
    programs.bun.enable = true;
    programs.gh.enable = true;
    programs.opencode = {
      enable = false; # use homebrew
    };

    # computer-use / spawn-subagent 与 skills 同源，软链到工作树源码即时生效
    home.file.".local/bin/computer-use" = {
      source = config.lib.file.mkOutOfStoreSymlink "${skillsDir}/computer-use-best-practice/scripts/computer-use.ts";
      force = true;
    };
    home.file.".local/bin/spawn-subagent" = {
      source = config.lib.file.mkOutOfStoreSymlink "${skillsDir}/subagent-policy/spawn-subagent";
      force = true;
    };

    home.packages = [
      ctx7
      pkgs.ast-grep
      # bil
      # twitter
      lit
      pkgs.imagemagick
    ];
  };
}
