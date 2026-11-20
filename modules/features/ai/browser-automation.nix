{ config, ... }:
{
  flake.modules.darwin.workstation.imports = [ config.flake.modules.darwin.browser-automation ];

  flake.modules.darwin.browser-automation.homebrew.casks = [ "google-chrome" ];

  flake.modules.homeManager.browser-automation =
    let
      chrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
    in
    {
      home.file.".agent-browser/config.json".text = builtins.toJSON { executablePath = chrome; };

      home.sessionVariables = {
        AGENT_BROWSER_NO_VERSION_CHECK = "1";
        NO_UPDATE_NOTIFIER = "1";
      };
    };
}
