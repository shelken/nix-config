{
  myvars,
  ...
}:
###################################################################################
#
#  macOS's System configuration
#
#  All the configuration options are documented here:
#    https://daiderd.com/nix-darwin/manual/index.html#sec-options
#  Incomplete list of macOS `defaults` commands :
#    https://github.com/yannbertrand/macos-defaults
#
#
# NOTE: Some options are not supported by nix-darwin directly, manually set them:
#   1. To avoid conflicts with neovim, disable ctrl + up/down/left/right to switch spaces in:
#     [System Preferences] -> [Keyboard] -> [Keyboard Shortcuts] -> [Mission Control]
#   2. Disable use Caps Lock as 中/英 switch in:
#     [System Preferences] -> [Keyboard] -> [Input Sources] -> [Edit] -> [Use 中/英 key to switch ] -> [Disable]
###################################################################################
{
  # Add ability to used TouchID for sudo authentication
  # https://github.com/LnL7/nix-darwin/blob/991bb2f6d46fc2ff7990913c173afdb0318314cb/modules/security/pam.nix
  security.pam.services.sudo_local = {
    touchIdAuth = true;
    watchIdAuth = true;
    reattach = true;
  };

  # 系统级切换提权时保留 SSH_AUTH_SOCK，供内嵌的 Home Manager 激活与私有仓库访问
  security.sudo.extraConfig = ''
    Defaults:${myvars.username} env_keep += "SSH_AUTH_SOCK"
  '';

  system = {
    # activationScripts are executed every time you boot the system or run `nixos-rebuild` / `darwin-rebuild`.
    activationScripts.postActivation.text = ''
      # 部分设置仍需重启应用或重新登录；此命令不能保证所有偏好立即生效。
      sudo -u ${myvars.username} /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u
    '';

    primaryUser = "${myvars.username}";

    # ref: https://mynixos.com/nix-darwin/options/system.defaults
    defaults = {
      menuExtraClock.Show24Hour = true; # show 24 hour clock

      # customize dock
      dock = {
        autohide = true; # automatically hide and show the dock
        show-recents = false; # do not show recent apps in dock
        # do not automatically rearrange spaces based on most recent use.
        mru-spaces = false;

        # customize Hot Corners(触发角, 鼠标移动到屏幕角落时触发的动作) 1为无动作
        wvous-tl-corner = 1; # 左上：无操作
        wvous-tr-corner = 4; # 右上：显示桌面
        # 11 是旧 Launchpad 编号；新版 Apps 的编号未实测，保留现值。
        wvous-bl-corner = 11;
        wvous-br-corner = 1; # 右下：无操作
      };

      # customize finder
      finder = {
        _FXShowPosixPathInTitle = true; # show full path in finder title
        # AppleShowAllExtensions = true; # show all file extensions
        FXEnableExtensionChangeWarning = false; # disable warning when changing file extension
        QuitMenuItem = true; # enable quit menu item
        ShowPathbar = true; # show path bar
        ShowStatusBar = true; # show status bar
        AppleShowAllFiles = true;
        ShowExternalHardDrivesOnDesktop = true;
        ShowHardDrivesOnDesktop = true;
        ShowMountedServersOnDesktop = true;
        ShowRemovableMediaOnDesktop = true;
        _FXSortFoldersFirst = true;
        FXDefaultSearchScope = "SCcf";
      };

      # customize trackpad
      trackpad = {
        # tap - 轻触触摸板, click - 点击触摸板
        Clicking = true; # enable tap to click(轻触触摸板相当于点击)
        TrackpadRightClick = true; # enable two finger right click
        TrackpadThreeFingerDrag = true; # enable three finger drag
      };

      # customize macOS
      NSGlobalDomain = {
        # `defaults read NSGlobalDomain "xxx"`
        "com.apple.swipescrolldirection" = true; # enable natural scrolling(default to true)
        "com.apple.sound.beep.feedback" = 0; # disable beep sound when pressing volume up/down key

        # Appearance
        # AppleInterfaceStyle = "Dark"; # dark mode

        # AppleKeyboardUIMode = 3; # Mode 3 enables full keyboard control.
        # 支持长按选字的应用会优先显示选字菜单，不保证按住字母连续输入。
        ApplePressAndHoldEnabled = true;
        InitialKeyRepeat = 15;
        KeyRepeat = 2;
        AppleSpacesSwitchOnActivate = true;
        AppleShowScrollBars = "WhenScrolling";
        AppleIconAppearanceTheme = "RegularAutomatic";

        NSAutomaticCapitalizationEnabled = false; # disable auto capitalization(自动大写)
        NSAutomaticDashSubstitutionEnabled = false; # disable auto dash substitution(智能破折号替换)
        NSAutomaticPeriodSubstitutionEnabled = false; # disable auto period substitution(智能句号替换)
        NSAutomaticQuoteSubstitutionEnabled = false; # disable auto quote substitution(智能引号替换)
        NSAutomaticSpellingCorrectionEnabled = false; # disable auto spelling correction(自动拼写检查)
        NSNavPanelExpandedStateForSaveMode = true; # expand save panel by default(保存文件时的路径选择/文件名输入页)
        NSNavPanelExpandedStateForSaveMode2 = true;

        # finder
        AppleShowAllExtensions = true;
      };

      # 使用模块布尔类型，避免自定义域绕过类型检查或重复覆盖。
      spaces.spans-displays = true;
      WindowManager = {
        AppWindowGroupingBehavior = true;
        EnableStandardClickToShowDesktop = false;
        HideDesktop = false;
        StandardHideDesktopIcons = false;
        StageManagerHideWidgets = false;
        StandardHideWidgets = false;
      };

      # customize settings that not supported by nix-darwin directly
      # Incomplete list of macOS `defaults` commands :
      #   https://github.com/yannbertrand/macos-defaults
      CustomUserPreferences = {
        # NSGlobalDomain 与 .GlobalPreferences 指向同一域，集中声明避免分散覆盖。
        NSGlobalDomain = {
          AppleAccentColor = 6; # 粉色
          AppleHighlightColor = "1.000000 0.749020 0.823529 Pink"; # 高亮色
          AppleIconAppearanceTintColor = "Other";
          AppleICUForce24HourTime = true;
          AppleICUForce12HourTime = false; # 系统设置之后发现两个并存
          AppleIconAppearanceCustomTintColor = "0.475000 0.822795 1.000000 0.845588";
          AppleLanguages = [
            "zh-Hans-${myvars.region}"
            "zh-Hant-${myvars.region}"
            "en-${myvars.region}"
          ];
          AppleFirstWeekday.gregorian = 2;
          AppleICUDateFormatStrings."1" = "y-MM-dd";

          # Add a context menu item for showing the Web Inspector in web views
          WebKitDeveloperExtras = true;
        };
        "com.apple.desktopservices" = {
          # Avoid creating .DS_Store files on network or USB volumes
          DSDontWriteNetworkStores = true;
          DSDontWriteUSBStores = true;
        };
        # "com.apple.screensaver" = {
        #   # Require password immediately after sleep or screen saver begins
        #   askForPassword = 1;
        #   askForPasswordDelay = 0;
        # };
        # "com.apple.screencapture" = {
        #   location = "~/Desktop";
        #   type = "png";
        # };
        "com.apple.AdLib" = {
          allowApplePersonalizedAdvertising = false;
        };
        # Prevent Photos from opening automatically when devices are plugged in
        "com.apple.ImageCapture".disableHotPlug = true;
        # Stats
        "eu.exelban.Stats" = {
          # 登录项由 SMAppService 管理；不写 LaunchAtLoginNext/runAtLoginInitialized 迁移标记。
          Network_state = true;
        };
        # Helium Browser
        "net.imput.helium" = {
          NSUserKeyEquivalents = {
            "选择上一个标签" = "@←";
            "选择下一个标签" = "@→";
          };
        };
        # Chrome Browser
        "com.google.Chrome" = {
          NSUserKeyEquivalents = {
            "选择上一个标签" = "@←";
            "选择下一个标签" = "@→";
          };
        };
      };

      loginwindow = {
        GuestEnabled = false; # disable guest user
        SHOWFULLNAME = false; # show full name in login window
      };
    };

    # keyboard settings is not very useful on macOS
    # the most important thing is to remap option key to alt key globally,
    # but it's not supported by macOS yet.
    keyboard = {
      enableKeyMapping = false; # enable key mapping so that we can use `option` as `control`

      # NOTE: do NOT support remap capslock to both control and escape at the same time
      # remapCapsLockToControl = true; # remap caps lock to control, useful for emacs users
      # remapCapsLockToEscape = true; # remap caps lock to escape, useful for vim users

      # swap left command and left alt
      # so it matches common keyboard layout: `ctrl | command | alt`
      #
      # disabled, caused only problems!
      # swapLeftCommandAndLeftAlt = true;

      # userKeyMapping = [
      #   # remap escape to caps lock
      #   # so we swap caps lock and escape, then we can use caps lock as escape
      #   {
      #     HIDKeyboardModifierMappingSrc = 30064771113;
      #     HIDKeyboardModifierMappingDst = 30064771129;
      #   }
      # ];
    };
  };
}
