# Android 调试工具：adb / scrcpy，跨平台
{ config, ... }:
{
  # 原属 gui 全覆盖，跨平台无 darwin 专属
  flake.modules.darwin.gui.imports = [ config.flake.modules.darwin.android-tools ];
  flake.modules.nixos.gui.imports = [ config.flake.modules.nixos.android-tools ];

  flake.modules.homeManager.android-tools =
    { pkgs, ... }:
    {
      programs.television.enable = true; # catppuccin 主题经 autoEnable 注入
      home.packages = with pkgs; [
        android-tools
        scrcpy
      ];
    };
}
