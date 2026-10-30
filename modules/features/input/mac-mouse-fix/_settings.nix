{
  General = {
    buttonKillSwitch = false;
    checkForPrereleases = false;
    checkForUpdates = true;
    lockPointerDuringDrag = false;
    scrollKillSwitch = false;
    showMenuBarItem = true;
  };
  Pointer = {
    acceleration = 0.6875;
    sensitivity = 1;
    useSystemAcceleration = false;
  };
  Remaps = [
    {
      effect = {
        button = 3;
        nOfClicks = 1;
        type = "mouseButton";
      };
      modifiers = { };
      trigger = {
        button = 3;
        duration = "click";
        level = 1;
      };
    }
    {
      effect = {
        modifiedDragType = "twoFingerSwipe";
      };
      modifiers = {
        buttonModifiers = [
          {
            button = 3;
            level = 1;
          }
        ];
      };
      trigger = "dragTrigger";
    }
    {
      effect = {
        type = "navigationSwipe";
        variant = "left";
      };
      modifiers = { };
      trigger = {
        button = 4;
        duration = "click";
        level = 1;
      };
    }
    {
      effect = {
        flags = 524576;
        keycode = 0;
        type = "keyboardShortcut";
      };
      modifiers = { };
      trigger = {
        button = 4;
        duration = "hold";
        level = 1;
      };
    }
    {
      effect = {
        flags = 524576;
        keycode = 36;
        type = "keyboardShortcut";
      };
      modifiers = { };
      trigger = {
        button = 4;
        duration = "click";
        level = 2;
      };
    }
    {
      effect = {
        modifiedScrollEffectModification = "zoom";
      };
      modifiers = {
        buttonModifiers = [
          {
            button = 4;
            level = 1;
          }
        ];
      };
      trigger = "scrollTrigger";
    }
    {
      effect = {
        type = "navigationSwipe";
        variant = "right";
      };
      modifiers = { };
      trigger = {
        button = 5;
        duration = "click";
        level = 1;
      };
    }
    {
      effect = {
        modifiedScrollEffectModification = "fourFingerPinch";
      };
      modifiers = {
        buttonModifiers = [
          {
            button = 5;
            level = 1;
          }
        ];
      };
      trigger = "scrollTrigger";
    }
  ];
  Scroll = {
    modifiers = {
      horizontal = 131072;
      precise = 524288;
      swift = 262144;
      zoom = 1048576;
    };
    precise = false;
    reverseDirection = false;
    smooth = "high";
    speed = "medium";
    trackpadSimulation = true;
  };
}
