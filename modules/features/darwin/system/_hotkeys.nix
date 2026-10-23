{ lib, ... }:
let
  # ref: https://github.com/fullmetalsheep/nix-misc/blob/main/disable-apple-shortcuts/disable-apple-default-hotkeys.nix
  # some "Sensible" enums for AppleSymbolicHotKeys IDs based on their function.
  hotkeyEnums = {
    moveFocusToMenuBar = 7; # Control-fn-F2
    moveFocusToDock = 8; # Control-fn-F3
    moveFocusToActiveOrNextWindow = 9; # Control-fn-F4
    moveFocusToWindowToolbar = 10; # Control-fn-F5
    moveFocusToFloatingWindow = 11; # Control-fn-F6
    turnKeyboardAccessOnOrOff = 12; # Control-fn-F1
    changeWayTabMovesFocus = 13; # Control-fn-F7
    moveFocusToNextWindow = 27; # Command-`
    saveScreenToFile = 28; # Shift-Command-3
    copyScreenToClipboard = 29; # Control-Shift-Command-3
    saveSelectionToFile = 30; # Shift-Command-4
    copySelectionToClipboard = 31; # Control-Shift-Command-4
    missionControl = 32; # Control-UpArrow (standard key combination)
    missionControlDedicatedKey = 34; # Control-UpArrow (often for a dedicated key like F3, params differ)
    applicationWindows = 35; # Control-DownArrow
    showDesktop = 36; # fn-F11 (standard key combination)
    showDesktopDedicatedKey = 37; # fn-F11 (often for a dedicated key, params differ)
    moveFocusToWindowDrawer = 51; # Option-Command-'
    turnDockHidingOnOff = 52; # Option-Command-D
    decreaseDisplayBrightness = 53; # fn-F14 (standard key combination)
    increaseDisplayBrightness = 54; # fn-F15 (standard key combination)
    decreaseDisplayBrightnessDedicatedKey = 55; # fn-F14 (dedicated key, params differ)
    increaseDisplayBrightnessDedicatedKey = 56; # fn-F15 (dedicated key, params differ)
    moveFocusToStatusMenus = 57; # Control-fn-F8
    selectPreviousInputSource = 60; # Control-Space bar (if multiple inputs)
    selectNextInputSource = 61; # '^ + Option + Space' for selecting the next input source
    showSpotlightSearch = 64; # Command-Space bar
    showSpotlightSearchInFinder = 65; # 访达搜索窗口 Disable 'Cmd + Alt + Space' for Finder search window
    moveLeftASpace = 79; # Control-LeftArrow (standard key combination)
    moveLeftASpaceDedicatedKey = 80; # Control-LeftArrow (dedicated key, params differ)
    moveRightASpace = 81; # Control-RightArrow (standard key combination)
    moveRightASpaceDedicatedKey = 82; # Control-RightArrow (dedicated key, params differ)
    switchToDesktop1 = 118; # Control-1
    switchToDesktop2 = 119; # Control-2
    switchToDesktop3 = 120; # Control-3
    showLaunchpad = 160; # None (default is disabled)
    showNotificationCenter = 163; # None (default is disabled)
    turnDoNotDisturbOnOff = 175; # None (default is disabled)
    saveTouchBarToFile = 181; # Shift-Command-6 (Touch Bar specific)
    copyTouchBarToClipboard = 182; # Control-Shift-Command-6 (Touch Bar specific)
    screenshotAndRecordingOptions = 184; # Shift-Command-5
  };

  editMe_disableHotKeys = with hotkeyEnums; [
    selectNextInputSource
    showSpotlightSearch
    showSpotlightSearchInFinder
  ];

  uniqueSortedHotkeyIntegerIdsToDisable = lib.sort lib.lessThan editMe_disableHotKeys;

  appleSymbolicHotkeysSettings = lib.listToAttrs (
    map (id: {
      name = builtins.toString id; # Hotkey ID as a string key
      value = {
        enabled = false;
      };
    }) uniqueSortedHotkeyIntegerIdsToDisable
  );
in
{
  system.defaults.CustomUserPreferences."com.apple.symbolichotkeys" = {
    AppleSymbolicHotKeys = appleSymbolicHotkeysSettings;
  };
}
