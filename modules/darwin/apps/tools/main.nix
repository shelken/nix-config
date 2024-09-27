{
  lib,
  mylib,
  config,
  ...
}: let
  inherit (lib) mkIf;
  inherit (mylib) mkBoolOpt;
  cfg = config.shelken.tools.main;
in {
  options.shelken.tools.main = {
    enable = mkBoolOpt false "Whether or not to enable.";
  };

  config = mkIf cfg.enable {
    homebrew = {
      casks = [
        # translation
        "easydict" # 翻译
        # display
        "betterdisplay" # 显示器
        # mouse
        "mac-mouse-fix" # 鼠标滚动
        # "mos"
        # download
        "motrix" # 种子下载
      ];
    };
  };
}
