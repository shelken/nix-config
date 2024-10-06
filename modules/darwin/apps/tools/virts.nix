{
  lib,
  mylib,
  config,
  ...
}: let
  inherit (lib) mkIf;
  inherit (mylib) mkBoolOpt;
  cfg = config.shelken.tools.virts;
in {
  options.shelken.tools.virts = {
    enable = mkBoolOpt false "Whether or not to enable.";
  };

  config = mkIf cfg.enable {
    homebrew = {
      casks = [
        "utm" # 虚拟机
        "crystalfetch" # （ui） uupdump 下载 windows iso镜像
      ];
    };
  };
}
