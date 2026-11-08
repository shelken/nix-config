{
  # cua-driver 是 CuaDriver.app 里的二进制；官方不再通过 pip/mise 分发
  flake.modules.darwin.ai.homebrew.casks = [ "cuadriver" ];

  flake.modules.homeManager.ai.shelken.dev.sandbox.hostCommands.cua-driver =
    "cua-driver 控制宿主 macOS 图形界面，沙箱内无法访问宿主窗口";
}
