{
  myvars,
  ...
}:
{
  security.pam.services.sudo_local = {
    touchIdAuth = true;
    watchIdAuth = true;
    reattach = true;
  };

  security.sudo.extraConfig = ''
    Defaults:${myvars.username} env_keep += "SSH_AUTH_SOCK"
  '';

  time.timeZone = myvars.timeZone;

  system = {
    activationScripts.postActivation.text = ''
      sudo -u ${myvars.username} /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u
    '';

    primaryUser = "${myvars.username}";

    defaults = {
      dock = {
        autohide = true;
        show-recents = false;
        mru-spaces = false;

        wvous-tl-corner = 1; # 左上：无操作
        wvous-tr-corner = 4; # 右上：显示桌面
        wvous-bl-corner = 11;
        wvous-br-corner = 1;
      };

      finder = {
        _FXShowPosixPathInTitle = true;
        FXEnableExtensionChangeWarning = false;
        QuitMenuItem = true;
        ShowPathbar = true;
        ShowStatusBar = true;
        AppleShowAllFiles = true;
        ShowExternalHardDrivesOnDesktop = true;
        ShowHardDrivesOnDesktop = true;
        ShowMountedServersOnDesktop = true;
        ShowRemovableMediaOnDesktop = true;
        _FXSortFoldersFirst = true;
        FXDefaultSearchScope = "SCcf";
      };

      trackpad = {
        Clicking = true;
        TrackpadRightClick = true;
        TrackpadThreeFingerDrag = true;
      };

      NSGlobalDomain = {
        "com.apple.swipescrolldirection" = true;
        "com.apple.sound.beep.feedback" = 0;

        ApplePressAndHoldEnabled = true;
        InitialKeyRepeat = 15;
        KeyRepeat = 2;
        AppleSpacesSwitchOnActivate = true;
        AppleShowScrollBars = "WhenScrolling";
        AppleIconAppearanceTheme = "RegularAutomatic";

        NSAutomaticCapitalizationEnabled = false;
        NSAutomaticDashSubstitutionEnabled = false;
        NSAutomaticPeriodSubstitutionEnabled = false;
        NSAutomaticQuoteSubstitutionEnabled = false;
        NSAutomaticSpellingCorrectionEnabled = false;
        NSNavPanelExpandedStateForSaveMode = true;
        NSNavPanelExpandedStateForSaveMode2 = true;

        AppleShowAllExtensions = true;
      };

      spaces.spans-displays = true;
      WindowManager = {
        AppWindowGroupingBehavior = true;
        EnableStandardClickToShowDesktop = false;
        HideDesktop = false;
        StandardHideDesktopIcons = false;
        StageManagerHideWidgets = false;
        StandardHideWidgets = false;
      };

      CustomUserPreferences = {
        NSGlobalDomain = {
          AppleAccentColor = 6;
          AppleHighlightColor = "1.000000 0.749020 0.823529 Pink";
          AppleIconAppearanceTintColor = "Other";
          AppleICUForce24HourTime = true;
          AppleICUForce12HourTime = false; # 12h 键优先：为 true 时无论 24h 键为何值都走 12h
          AppleIconAppearanceCustomTintColor = "0.475000 0.822795 1.000000 0.845588";
          AppleLanguages = [
            "zh-Hans-${myvars.region}"
            "zh-Hant-${myvars.region}"
            "en-${myvars.region}"
          ];
          AppleFirstWeekday.gregorian = 2;
          AppleICUDateFormatStrings."1" = "y-MM-dd";

          WebKitDeveloperExtras = true;
        };
        "com.apple.desktopservices" = {
          DSDontWriteNetworkStores = true;
          DSDontWriteUSBStores = true;
        };
        "com.apple.AdLib" = {
          allowApplePersonalizedAdvertising = false;
        };
        "com.apple.ImageCapture".disableHotPlug = true;
        "eu.exelban.Stats" = {
          Network_state = true;
        };
        "com.google.Chrome" = {
          NSUserKeyEquivalents = {
            "选择上一个标签" = "@←";
            "选择下一个标签" = "@→";
          };
        };
      };

      loginwindow = {
        GuestEnabled = false;
        SHOWFULLNAME = false;
      };
    };

    keyboard = {
      enableKeyMapping = false;

    };
  };
}
