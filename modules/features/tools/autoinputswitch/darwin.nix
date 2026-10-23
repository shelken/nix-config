# 自动输入法切换：所在角色的主机即启用；
# 主机可设 shelken.tools.autoinputswitch.app 切换软件，HM 部分经 osConfig 读取同一值
{ config, ... }:
{
  # 加入哪一层只在这里声明，主机不直接导入具体功能
  flake.modules.darwin.workstation.imports = [ config.flake.modules.darwin.autoinputswitch ];

  flake.modules.darwin.autoinputswitch =
    { lib, config, ... }:
    let
      inherit (config.shelken.tools.autoinputswitch) app;
    in
    {
      options.shelken.tools.autoinputswitch.app = lib.mkOption {
        type = lib.types.enum [
          "typeswitch"
          "inputsourcepro"
        ];
        default = "typeswitch";
        description = "选择使用哪个自动输入法切换软件";
      };

      config = lib.mkMerge [
        (lib.mkIf (app == "typeswitch") {
          homebrew.casks = [ "shelken/tap/typeswitch" ];

          launchd.user.agents.autoinputswitch = {
            command = ''"/Applications/TypeSwitch.app/Contents/MacOS/TypeSwitch"'';
            serviceConfig.RunAtLoad = true;
          };
        })
        (lib.mkIf (app == "inputsourcepro") {
          homebrew.casks = [ "shelken/tap/input-source-pro-beta" ];

          system.defaults.CustomUserPreferences."space.ooooo.Input-Source-Pro.Beta" = {
            isRestorePreviouslyUsedInputSource = false;
            isActiveWhenSwitchApp = false;
          };
        })
      ];
    };
}
