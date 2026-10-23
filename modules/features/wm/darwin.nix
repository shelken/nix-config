# 窗口管理器：二选一（aerospace / omniwm）
# 加入 gui 角色；mio 选 omniwm，其余桌面机用默认 aerospace
{ config, ... }:
{
  flake.modules.darwin.gui.imports = [ config.flake.modules.darwin.wm ];

  flake.modules.darwin.wm =
    { lib, config, ... }:
    let
      inherit (config.shelken.wm) manager;
    in
    {
      options.shelken.wm.manager = lib.mkOption {
        type = lib.types.enum [
          "aerospace"
          "omniwm"
        ];
        default = "aerospace";
        description = "选择使用的平铺窗口管理器";
      };

      config = lib.mkMerge [
        (lib.mkIf (manager == "aerospace") {
          homebrew.casks = [ "aerospace" ];
        })
        (lib.mkIf (manager == "omniwm") {
          homebrew = {
            taps = [
              {
                name = "BarutSRB/tap";
                trusted = true;
              }
            ];
            casks = [ "omniwm" ];
          };
        })
      ];
    };
}
