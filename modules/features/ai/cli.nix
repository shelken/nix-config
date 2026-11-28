{
  flake.modules.homeManager.ai =
    {
      pkgs,
      ...
    }:
    {
      config = {
        programs.opencode = {
          enable = false;
        };

        home.packages = [
          pkgs.ast-grep
          pkgs.imagemagick
        ];

        programs.mise.globalConfig.tools = {
          herdr = "latest";
          # renovate: datasource=npm depName=ctx7
          "npm:ctx7" = "0.12.2";
          "npm:@seflless/deepwiki" = {
            # renovate: datasource=npm depName=@seflless/deepwiki
            version = "0.1.8";
            allow_low_downloads = true;
          };
          # renovate: datasource=npm depName=@llamaindex/liteparse
          "npm:@llamaindex/liteparse" = "2.21.4";
          # renovate: datasource=github-releases depName=rtk-ai/rtk
          rtk = "1.2";
        };
      };
    };
}
