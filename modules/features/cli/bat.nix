{ config, ... }:
{
  flake.modules.homeManager.core.imports = [ config.flake.modules.homeManager.bat ];

  flake.modules.homeManager.bat =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      programs.bat = {
        enable = true;
        config = {
          pager = "less -FR";
        };
      };

      # EXTERNAL: bat 只从缓存读 HM 注入的 catppuccin 主题，须每次重建；HM 默认脚本多打印三行，故覆写丢弃 stdout
      home.activation.batCache = lib.mkForce (
        lib.hm.dag.entryAfter [ "linkGeneration" ] ''
          (
            export XDG_CACHE_HOME=${lib.escapeShellArg config.xdg.cacheHome}
            # EXTERNAL: 上游 bat#1726 未修：cache 目录已存在时 bat cache --build 失败，只能在空目录构建
            cd "${pkgs.emptyDirectory}"
            run ${lib.getExe config.programs.bat.package} cache --build > /dev/null
          )
        ''
      );
    };
}
