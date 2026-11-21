{ lib, ... }:
let
  # ref: https://github.com/fullmetalsheep/nix-misc/blob/main/disable-apple-shortcuts/disable-apple-default-hotkeys.nix
  hotkeyEnums = {
    moveFocusToMenuBar = 7;
    moveFocusToDock = 8;
    moveFocusToActiveOrNextWindow = 9;
    moveFocusToWindowToolbar = 10;
    moveFocusToFloatingWindow = 11;
    turnKeyboardAccessOnOrOff = 12;
    changeWayTabMovesFocus = 13;
    moveFocusToNextWindow = 27;
    saveScreenToFile = 28;
    copyScreenToClipboard = 29;
    saveSelectionToFile = 30;
    copySelectionToClipboard = 31;
    missionControl = 32;
    missionControlDedicatedKey = 34;
    applicationWindows = 35;
    showDesktop = 36;
    showDesktopDedicatedKey = 37;
    moveFocusToWindowDrawer = 51;
    turnDockHidingOnOff = 52;
    decreaseDisplayBrightness = 53;
    increaseDisplayBrightness = 54;
    decreaseDisplayBrightnessDedicatedKey = 55;
    increaseDisplayBrightnessDedicatedKey = 56;
    moveFocusToStatusMenus = 57;
    selectPreviousInputSource = 60;
    selectNextInputSource = 61;
    showSpotlightSearch = 64;
    showSpotlightSearchInFinder = 65;
    moveLeftASpace = 79;
    moveLeftASpaceDedicatedKey = 80;
    moveRightASpace = 81;
    moveRightASpaceDedicatedKey = 82;
    switchToDesktop1 = 118;
    switchToDesktop2 = 119;
    switchToDesktop3 = 120;
    showLaunchpad = 160;
    showNotificationCenter = 163;
    turnDoNotDisturbOnOff = 175;
    saveTouchBarToFile = 181;
    copyTouchBarToClipboard = 182;
    screenshotAndRecordingOptions = 184;
  };

  editMe_disableHotKeys = with hotkeyEnums; [
    selectNextInputSource
    showSpotlightSearch
    showSpotlightSearchInFinder
  ];

  uniqueSortedHotkeyIntegerIdsToDisable = lib.sort lib.lessThan editMe_disableHotKeys;

  appleSymbolicHotkeysSettings = lib.listToAttrs (
    map (id: {
      name = builtins.toString id;
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
