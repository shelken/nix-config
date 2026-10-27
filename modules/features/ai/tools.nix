# 共享工具登记表：ai 侧条目（omp/pi/codex/claude-code/bun，ADR 0003）
# omp postInstall 承接原 home.activation.installOmpPlugins 的插件补齐逻辑。
{
  config,
  lib,
  ...
}:
{
  flake.modules.homeManager.ai.shelken.dev.tools = {
    # mise 共享工具
    # 1.3.13 无 BUN_CONFIG_HTTP_IDLE_TIMEOUT，安装会在半开连接上永久挂起
    bun.mise = "1.4.2";
    codex.mise = "0.160.1";
    claude-code.mise = "2.1.304";
    omp = {
      mise = {
        name = "oh-my-pi";
        version = "latest";
        minimum_release_age = "0h";
      };
      # 插件目录每次都与清单严格对齐：清单之外的条目删除，清单内的重新安装。
      # 宿主激活与沙箱 sb sync 共用 install.sh。清单路径在运行时决定：guest 由 guest-env.sh 导出
      # SB_OMP_MANIFEST 指向沙箱版清单（已按 sandboxExclude 过滤），宿主没有该变量，用仓库原件。
      postInstall = ''
        bash ${./omp/plugins/install.sh} "''${SB_OMP_MANIFEST:-${./omp/plugins/package.json}}"
      '';
    };
    pi = {
      mise = {
        name = "npm:@earendil-works/pi-coding-agent";
        version = "latest";
        minimum_release_age = "0h";
      };
    };
  };
}
