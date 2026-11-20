{
  flake.modules.homeManager.ai =
    {
      pkgs,
      ...
    }:
    let
      jsonFormat = pkgs.formats.json { };
    in
    {
      shelken.dev.tools.agent-common.files = {
        ".config/ponytail/config.json".source = jsonFormat.generate "ponytail-config.json" {
          defaultMode = "off";
          hideStatus = true;
          quietStartup = true;
        };

        ".config/rpiv-web-tools/config.json".source = jsonFormat.generate "rpiv-web-tools-config.json" {
          interceptors = {
            github = true;
          };
          provider = "exa";
        };
      };

      shelken.dev.tools.agent-common.env.FFF_ENABLE_HOME_SCAN = "0";

      shelken.dev.tools.pi.files = {
        # pi-fff 插件固定使用这个目录寻找持久化配置：PI_CODING_AGENT_DIR 未设置时，
        # pi 与 omp 的 piDataDir() 都解析到此处，两边共用同一份设置。
        ".pi/agent/pi-fff.json" = {
          source = jsonFormat.generate "pi-fff.json" {
            mode = "override";
          };
          force = true;
        };

        # pi-intercom 的配置路径由 getAgentDirPath() 决定：$PI_CODING_AGENT_DIR 未设置时是
        # ~/.pi/agent/intercom/config.json，没有单独的环境变量可改，且设了 PI_CODING_AGENT_DIR
        # 会让 OMP 绕开 XDG，所以沿用默认路径。
        ".pi/agent/intercom/config.json".source = jsonFormat.generate "pi-intercom-config.json" {
          inboundTrigger = "always";
        };
      };
    };
}
