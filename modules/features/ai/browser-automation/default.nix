{ config, ... }:
{
  flake.modules.darwin.workstation.imports = [ config.flake.modules.darwin.browser-automation ];

  flake.modules.darwin.browser-automation.homebrew.casks = [ "google-chrome" ];

  flake.modules.homeManager.browser-automation =
    { pkgs, ... }:
    let
      chrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
    in
    {
      shelken.dev.ai.skills = [
        ./agent-browser
        ./browser-best-practice
      ];

      shelken.dev.sandbox.hostCommands = {
        agent-browser = "agent-browser 驱动宿主 Chrome，沙箱内无法访问宿主图形浏览器";
        playwright-cli = "playwright-cli 通过 CDP 驱动宿主浏览器，沙箱内不可用";
      };

      home.packages = [ pkgs.agent-browser ];

      programs.mise.globalConfig.tools = {
        # renovate: datasource=npm depName=@playwright/cli
        "npm:@playwright/cli" = "0.1.25";
      };

      home.file.".agent-browser/config.json".text = builtins.toJSON { executablePath = chrome; };

      home.sessionVariables = {
        AGENT_BROWSER_NO_VERSION_CHECK = "1";
        NO_UPDATE_NOTIFIER = "1";
      };
    };
}
