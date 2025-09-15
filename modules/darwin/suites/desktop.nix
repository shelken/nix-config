{
  lib,
  mylib,
  config,
  pkgs,
  ...
}: let
  inherit (lib) mkIf;
  inherit (mylib) mkBoolOpt;
  cfg = config.shelken.suites.desktop;
in {
  options.shelken.suites.desktop = {
    enable = mkBoolOpt false "Whether or not to enable.";
  };

  config = mkIf cfg.enable {
    homebrew = {
      casks = [
        "easydict" # 翻译
        "betterdisplay" # 显示器
        "iina"

        # "microsoft-remote-desktop"
        # "vnc-viewer"

        # "keycastr" # an open source keystroke visualizer.
      ];
      masApps = {
        # Wechat = 836500024;
        # Xnip = 1221250572; # 截图
        DiskSpeedTest = 425264550; # 硬盘测速
      };
    };
    system.defaults.CustomUserPreferences = {
      "com.colliderli.iina" = {
        arrowBtnAction = 1; # 左右箭头按钮的功能 1 切换上下集 2 快进快退
      };
    };
    ### font 配置，所有mac引用desktop默认开启fonts
    shelken.modules.desktop.fonts.enable = true;
  };
}
