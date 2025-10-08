{
  config,
  lib,
  mylib,
  ...
}: let
  cfg = config.shelken.tools.screenshot;
in {
  options.shelken.tools.screenshot = {
    enable = mylib.mkBoolOpt false "Whether or not to enable.";
  };
  config = lib.mkIf cfg.enable {
    # 配置启动项(目前为 1Capture)
    home.activation.ScreenshotLoginItem = lib.hm.dag.entryAfter ["writeBoundary"] (
      mylib.mkLoginItemString {app_name = "1Capture";}
    );
  };
}
