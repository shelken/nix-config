{
  lib,
  mylib,
  config,
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
        # "google-chrome"
        "arc" # macOS 12+, browser
        "iina"
        "microsoft-remote-desktop"
        "vnc-viewer"
        "parsec"
        "keycastr" # an open source keystroke visualizer.
      ];
      masApps = {
        Wechat = 836500024;
        Xnip = 1221250572; # 截图
        DiskSpeedTest = 425264550; # 硬盘测速
        # vidhub = 1659622164;
      };
    };
  };
}
