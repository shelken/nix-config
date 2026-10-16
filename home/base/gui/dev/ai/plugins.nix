{
  pkgs,
  lib,
  config,
  ...
}:
let
  jsonFormat = pkgs.formats.json { };
in
{
  config = lib.mkIf config.shelken.dev.ai.enable {
    home.file = {
      ".config/ponytail/config.json".source = jsonFormat.generate "ponytail-config.json" {
        defaultMode = "off";
        hideStatus = true;
        quietStartup = true;
      };

      # pi-fff 插件固定使用这个目录寻找持久化配置：PI_CODING_AGENT_DIR 未设置时，
      # pi 与 omp 的 piDataDir() 都解析到此处，两边共用同一份设置。
      ".pi/agent/pi-fff.json" = {
        source = jsonFormat.generate "pi-fff.json" {
          mode = "override";
        };
        force = true;
      };

      ".config/rpiv-web-tools/config.json".source = jsonFormat.generate "rpiv-web-tools-config.json" {
        interceptors = {
          github = true;
        };
        provider = "exa";
      };
    };
  };
}
