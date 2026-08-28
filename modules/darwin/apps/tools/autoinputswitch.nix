# 自动输入法切换：darwin 侧（homebrew 安装 + launchd + 系统 defaults）。
# 用户态配置（app-rules / config.json）归 home 层 home/darwin/autoinputswitch.nix。
{
  lib,
  mylib,
  config,
  ...
}:
let
  inherit (lib)
    mkIf
    mkMerge
    mkOption
    types
    ;
  inherit (mylib) mkBoolOpt;
  cfg = config.shelken.tools.autoinputswitch;
in
{
  options.shelken.tools.autoinputswitch = {
    enable = mkBoolOpt false "是否启用自动输入法切换";
    app = mkOption {
      type = types.enum [
        "typeswitch"
        "inputsourcepro"
      ];
      default = "typeswitch";
      description = "选择使用哪个自动输入法切换软件";
    };
  };

  config = mkMerge [
    (mkIf (cfg.enable && cfg.app == "typeswitch") {
      homebrew.casks = [ "shelken/tap/typeswitch" ];

      launchd.user.agents.autoinputswitch = {
        command = ''"/Applications/TypeSwitch.app/Contents/MacOS/TypeSwitch"'';
        serviceConfig.RunAtLoad = true;
      };
    })
    (mkIf (cfg.enable && cfg.app == "inputsourcepro") {
      homebrew.casks = [ "shelken/tap/input-source-pro-beta" ];

      system.defaults.CustomUserPreferences."space.ooooo.Input-Source-Pro.Beta" = {
        isRestorePreviouslyUsedInputSource = false;
        isActiveWhenSwitchApp = false;
      };
    })
  ];
}
