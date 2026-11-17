# Node 生态：pnpm、npm 与 bun 的网络设置；nodejs 本体由共享工具登记表提供（shelken.dev.tools，ADR 0003）
# 开发机 → tui
{ config, ... }:
{
  flake.modules.homeManager.tui.imports = [ config.flake.modules.homeManager.node ];

  flake.modules.homeManager.node =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.pnpm ];
      programs.npm.enable = true;
      # nodejs 由共享工具登记表提供（shelken.dev.tools），避免重复安装
      programs.npm.package = null;
      programs.npm.settings = {
        prefix = "\${HOME}/.npm-global";
        # registry = "https://registry.npmmirror.com";
        min-release-age = 3;
        # 半开连接快速失败，不拉长重试等待
        fetch-timeout = 15000;
        fetch-retries = 1;
        fetch-retry-mintimeout = 500;
        fetch-retry-maxtimeout = 2000;
        maxsockets = 15;
      };

      # Bun HTTP 空闲超时/重试（IDLE 仅 1.3.14+；偏快速失败）
      home.sessionVariables = {
        BUN_CONFIG_HTTP_IDLE_TIMEOUT = "5";
        BUN_CONFIG_HTTP_RETRY_COUNT = "1";
      };
    };
}
