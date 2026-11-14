# 自动化专用的 Chrome：agent-browser、playwright-cli 都用它，不自动下载浏览器；日常浏览器是 Helium
{ config, ... }:
{
  flake.modules.darwin.workstation.imports = [ config.flake.modules.darwin.browser-automation ];

  flake.modules.darwin.browser-automation.homebrew.casks = [ "google-chrome" ];

  flake.modules.homeManager.browser-automation =
    let
      chrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
    in
    {
      # 显式指路：避免哪天有人跑 `agent-browser install` 后，自动发现改选下载的 Chrome for Testing。
      # 路径类的键只在用户级配置生效，项目里的 agent-browser.json 会忽略它们。
      # playwright-cli 不用配：默认就启动系统 Chrome
      home.file.".agent-browser/config.json".text = builtins.toJSON { executablePath = chrome; };

      home.sessionVariables = {
        # 版本由 mise 钉死，关掉它们的联网更新提示
        AGENT_BROWSER_NO_VERSION_CHECK = "1";
        NO_UPDATE_NOTIFIER = "1";
      };
    };
}
