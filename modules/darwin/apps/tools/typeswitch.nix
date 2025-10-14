{
  lib,
  mylib,
  config,
  ...
}:
let
  inherit (lib) mkIf;
  inherit (mylib) mkBoolOpt;
  cfg = config.shelken.tools.typeswitch;
  chinese = "im.rime.inputmethod.Squirrel.Hans";
  english = "com.apple.keylayout.ABC";
in
{
  options.shelken.tools.typeswitch = {
    enable = mkBoolOpt false "Whether or not to enable.";
  };

  # 目前问题：finder和kitty无法被管理

  config = mkIf cfg.enable {
    homebrew = {
      taps = [
        "shelken/tap"
      ];
      casks = [
        "typeswitch"
      ];
      brews = [
      ];
    };

    system.defaults.CustomUserPreferences."group.top.ygsgdbd.TypeSwitch" = {
      appInputMethodSettings = {
        # English
        "com.apple.finder" = english;
        "com.apple.Spotlight" = english;
        "com.microsoft.VSCode" = english;
        "com.raycast.macos" = english;
        "net.kovidgoyal.kitty" = english;
        "tv.parsec.www" = english;
        #-- 中文
        "com.apple.Notes" = chinese;
        "com.apple.Safari" = chinese;
        "com.google.Chrome" = chinese;
        "com.tencent.xinWeChat" = chinese;
        "md.obsidian" = chinese;
        "net.imput.helium" = chinese;
        "ru.keepcoder.Telegram" = chinese;
        "com.kangfenmao.CherryStudio" = chinese;
        "com.openai.chat" = chinese;
      };
    };

    # before: sudo xattr -r -d com.apple.quarantine /Applications/TypeSwitch.app
    launchd.user.agents.typeswitch = {
      command = ''"/Applications/TypeSwitch.app/Contents/MacOS/TypeSwitch"'';
      serviceConfig.RunAtLoad = true;
    };
  };
}
