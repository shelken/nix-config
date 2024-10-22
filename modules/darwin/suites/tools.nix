{
  lib,
  mylib,
  config,
  ...
}: let
  inherit (lib) mkIf;
  inherit (mylib) mkBoolOpt;
  cfg = config.shelken.suites.tools;
in {
  options.shelken.suites.tools = {
    enable = mkBoolOpt false "Whether or not to enable.";
  };

  config = mkIf cfg.enable {
    shelken.tools = {
      main.enable = true; # 主要
      music.enable = true; # 音乐刮削相关
      image.enable = true; # 图片处理
      virts.enable = true; # 虚拟机
      rclone.enable = true; # rclone
      others.enable = true; # 其他：altserver,备份
    };
  };
}
