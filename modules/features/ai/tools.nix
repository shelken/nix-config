# 共享工具登记表：ai 侧条目（omp/pi/bun，ADR 0003）。codex、claude-code 只在宿主用，不登记，见 ai-apps
{
  config,
  lib,
  ...
}:
{
  flake.modules.homeManager.ai.shelken.dev.tools = {
    # 1.3.13 无 BUN_CONFIG_HTTP_IDLE_TIMEOUT，安装会在半开连接上永久挂起
    # renovate: datasource=github-releases depName=oven-sh/bun extractVersion=^bun-v(?<version>.+)$
    bun.mise = "1.4.2";
    omp = {
      sandboxCommand = "omp";
      mise = {
        name = "oh-my-pi";
        version = "latest";
        minimum_release_age = "0h";
      };
      # OMP 只在 $XDG_DATA_HOME/omp 已存在时才把插件放进 XDG 目录
      sandboxDirs = [
        "$XDG_DATA_HOME/omp"
        "$XDG_STATE_HOME/omp"
        "$XDG_CACHE_HOME/omp"
      ];
      sandboxEnv = {
        SB_OMP_MANIFEST = "$SB_CONFIG_DIR/.omp/agent/plugins-package.json";
        SB_BUN_CACHE_DIR = "$SB_MISE_CACHE_DIR/bun-cache";
      };
      # 宿主激活与沙箱 sb sync 共用 install.sh。清单路径在运行时决定：guest 由 sandboxEnv 导出
      # SB_OMP_MANIFEST 指向沙箱版清单（已按 sandboxExclude 过滤），宿主没有该变量，用仓库原件。
      postInstall = ''
        bash ${./omp/plugins/install.sh} "''${SB_OMP_MANIFEST:-${./omp/plugins/package.json}}"
      '';
    };
    pi = {
      sandboxCommand = "pi";
      mise = {
        name = "npm:@earendil-works/pi-coding-agent";
        version = "latest";
        minimum_release_age = "0h";
      };
    };
  };
}
