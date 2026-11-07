# 窗口管理器：目前只有 omniwm；保留枚举，换实现时在这里加值
# 加入 gui 角色
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
        type = lib.types.enum [ "omniwm" ];
        default = "omniwm";
        description = "选择使用的平铺窗口管理器";
      };

      config = lib.mkIf (manager == "omniwm") {
        homebrew = {
          taps = [
            {
              name = "BarutSRB/tap";
              trusted = true;
            }
          ];
          casks = [ "omniwm" ];
        };
      };
    };
}
