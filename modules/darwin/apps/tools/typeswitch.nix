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
in
{
  options.shelken.tools.typeswitch = {
    enable = mkBoolOpt false "Whether or not to enable.";
  };

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
        "com.microsoft.VSCode" = "com.apple.keylayout.ABC";
        "com.raycast.macos" = "com.apple.keylayout.ABC";
        "md.obsidian" = "im.rime.inputmethod.Squirrel.Hans";
        "net.imput.helium" = "im.rime.inputmethod.Squirrel.Hans";
        "net.kovidgoyal.kitty" = "com.apple.keylayout.ABC";
        "tv.parsec.www" = "com.apple.keylayout.ABC";
      };
    };
  };
}
