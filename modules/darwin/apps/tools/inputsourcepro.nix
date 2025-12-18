{
  lib,
  mylib,
  config,
  myvars,
  ...
}:
let
  inherit (lib) mkIf;
  inherit (mylib) mkBoolOpt;
  cfg = config.shelken.tools.inputsourcepro;
  chinese = "im.rime.inputmethod.Squirrel.Hans";
  english = "com.apple.keylayout.ABC";

  # Generate JSON config for Input Source Pro
  configJson = builtins.toJSON {
    appRules = {
      # English
      "com.apple.finder" = english;
      "com.microsoft.VSCode" = english;
      "dev.zed.Zed" = english;
      "com.apple.dt.Xcode" = english;
      "net.kovidgoyal.kitty" = english;
      "tv.parsec.www" = english;
      "com.apple.ScreenSharing" = english;
      "com.apple.Safari" = english;
      "com.google.Chrome" = english;
      "net.imput.helium" = english;
      # Chinese
      "com.apple.Notes" = chinese;
      "com.tencent.xinWeChat" = chinese;
      "md.obsidian" = chinese;
      "ru.keepcoder.Telegram" = chinese;
      "com.kangfenmao.CherryStudio" = chinese;
      "com.openai.chat" = chinese;
      "com.anthropic.claudefordesktop" = chinese;
      "com.apple.MobileSMS" = chinese;
      "com.apple.systempreferences" = chinese;
    };
  };
in
{
  options.shelken.tools.inputsourcepro = {
    enable = mkBoolOpt false "Whether or not to enable Input Source Pro.";
  };

  config = mkIf cfg.enable {
    # Install via Homebrew
    homebrew.casks = [
      "input-source-pro-beta"
    ];

    # before: deq /Applications/Input\ Source\ Pro\ Beta.app
    launchd.user.agents.InputSourceProBeta = {
      command = ''"/Applications/Input Source Pro Beta.app/Contents/MacOS/Input Source Pro Beta"'';
      serviceConfig.RunAtLoad = true;
    };

    # Generate config file
    home-manager.users.${myvars.username}.home.file.".config/inputsourcepro/config.json".text =
      configJson;
  };
}
