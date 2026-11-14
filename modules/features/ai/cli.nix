{
  flake.modules.homeManager.ai =
    {
      pkgs,
      ...
    }:
    {
      config = {
        # bun/gh 由共享工具登记表提供（shelken.dev.tools，ADR 0003），不再各自 programs.* 声明
        programs.opencode = {
          enable = false; # use homebrew
        };

        home.packages = [
          pkgs.agent-browser
          pkgs.ast-grep
          pkgs.imagemagick
        ];

        # 需要较新版本、用 mise 管理更方便的 CLI
        programs.mise.globalConfig.tools = {
          # agent tools
          herdr = "latest";
          # renovate: datasource=npm depName=ctx7
          "npm:ctx7" = "0.11.1";
          # 周下载量不足 1000 会被 mise 拦下；0.1.8 源码已审，只访问官方 mcp.deepwiki.com
          "npm:@seflless/deepwiki" = {
            # renovate: datasource=npm depName=@seflless/deepwiki
            version = "0.1.8";
            allow_low_downloads = true;
          };
          # renovate: datasource=npm depName=@llamaindex/liteparse
          "npm:@llamaindex/liteparse" = "2.19.0";
          # renovate: datasource=npm depName=@playwright/cli
          "npm:@playwright/cli" = "0.1.24";
          # renovate: datasource=github-releases depName=rtk-ai/rtk
          rtk = "1.2";
          # "github:lycorp-jp/sim-use" = "0.14"; # ios 模拟器控制(暂时不使用 使用iphone-use-best-practice)
        };
      };
    };
}
