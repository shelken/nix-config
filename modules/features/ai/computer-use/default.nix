{ config, ... }:
{
  flake.modules.darwin.workstation.imports = [ config.flake.modules.darwin.computer-use ];

  flake.modules.darwin.computer-use.homebrew.casks = [ "cuadriver" ];

  flake.modules.homeManager.computer-use = {
    shelken.dev.ai.skills = [ ./computer-use-best-practice ];
    shelken.dev.sandbox.hostCommands.cua-driver = "cua-driver 控制宿主 macOS 图形界面，沙箱内无法访问宿主窗口";
  };
}
