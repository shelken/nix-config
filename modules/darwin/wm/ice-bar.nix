{
  lib,
  mylib,
  config,
  # options,
  ...
}: let
  inherit (lib) mkIf;
  inherit (mylib) mkBoolOpt;
  cfg = config.shelken.wm.iceBar;
in {
  options.shelken.wm.iceBar = {
    enable = mkBoolOpt false "Whether or not to enable.";
  };

  config = mkIf cfg.enable {
    # 版本差异的
    homebrew = {
      casks = [
        "jordanbaird-ice"
      ];
      brews = [
      ];
    };
    system.defaults.CustomUserPreferences."com.jordanbaird.Ice" = {
      AutoRehide = 1;
      CanToggleAlwaysHiddenSection = 1;
      # CustomIceIconIsTemplate = 0;
      # NSColorPanelMode = 4;
      # NSColorPickerPreferredRGBEntryMode = 2;
      SUAutomaticallyUpdate = 1;
      SUEnableAutomaticChecks = 1;
      # SUHasLaunchedBefore = 1;
      ShowIceIcon = 0;
      ShowOnClick = 1; # 点击后显示隐藏的
      ShowOnHover = 0;
      ShowOnScroll = 1;
      ShowSectionDividers = 0;
      UseIceBar = 1; # 在菜单下方显示隐藏的图标，而不是菜单栏
      # "hasMigrated0_8_0" = 1;
      # MenuBarAppearanceConfiguration = "{bytes = 0x7b226861 73426f72 64657222 3a66616c ... 2f5c2f38 3d227d7d }";
    };
  };
}
