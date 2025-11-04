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
        "dev.zed.Zed" = english;
        "com.apple.dt.Xcode" = english;
        "com.raycast.macos" = english; # raycast
        "net.kovidgoyal.kitty" = english;
        "tv.parsec.www" = english; # parsec
        "com.apple.ScreenSharing" = english;
        ## 浏览器
        "com.apple.Safari" = english;
        "com.google.Chrome" = english;
        "net.imput.helium" = english;
        #-- 中文
        "com.apple.Notes" = chinese; # 备忘录
        "com.tencent.xinWeChat" = chinese; # 微信
        "md.obsidian" = chinese;
        "ru.keepcoder.Telegram" = chinese;
        "com.kangfenmao.CherryStudio" = chinese;
        "com.openai.chat" = chinese; # chatgpt
        "com.anthropic.claudefordesktop" = chinese; # claude
        "com.apple.MobileSMS" = chinese; # 信息
        "com.apple.systempreferences" = chinese; # 系统偏好设置
      };
    };

    # before: sudo xattr -r -d com.apple.quarantine /Applications/TypeSwitch.app
    # launchd.user.agents.typeswitch = {
    #   command = ''"/Applications/TypeSwitch.app/Contents/MacOS/TypeSwitch"'';
    #   serviceConfig.RunAtLoad = true;
    # };
  };
}
