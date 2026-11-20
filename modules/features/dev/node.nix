{ config, ... }:
{
  flake.modules.homeManager.tui.imports = [ config.flake.modules.homeManager.node ];

  flake.modules.homeManager.node =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.pnpm ];
      programs.npm.enable = true;
      programs.npm.package = null;
      programs.npm.settings = {
        prefix = "\${HOME}/.npm-global";
        min-release-age = 3;
        fetch-timeout = 15000;
        fetch-retries = 1;
        fetch-retry-mintimeout = 500;
        fetch-retry-maxtimeout = 2000;
        maxsockets = 15;
      };

      home.sessionVariables = {
        BUN_CONFIG_HTTP_IDLE_TIMEOUT = "5";
        BUN_CONFIG_HTTP_RETRY_COUNT = "1";
      };
    };
}
