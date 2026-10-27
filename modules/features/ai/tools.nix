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
      # 插件按仓库清单补装，只补缺，不删除目录里已有的依赖（沙箱内手装的插件与已从清单删除的插件不被清理）。
      # 宿主激活与沙箱 sb sync 共用 install.sh，差异由它读环境变量决定，见脚本头部
      postInstall = ''
        bash ${./omp/plugins/install.sh} ${./omp/plugins/package.json}
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
