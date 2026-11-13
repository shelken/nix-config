# 桌面控制：cua-driver 读写宿主 macOS 窗口，只在工作站使用
{ config, ... }:
{
  flake.modules.darwin.workstation.imports = [ config.flake.modules.darwin.computer-use ];

  # cua-driver 是 CuaDriver.app 里的二进制；官方不再通过 pip/mise 分发
  flake.modules.darwin.computer-use.homebrew.casks = [ "cuadriver" ];

  flake.modules.homeManager.computer-use = {
    shelken.dev.ai.skills = [ ./computer-use-best-practice ];
    shelken.dev.sandbox.hostCommands.cua-driver = "cua-driver 控制宿主 macOS 图形界面，沙箱内无法访问宿主窗口";
  };
}
