{ config, ... }:
{
  flake.modules.darwin.workstation.imports = [ config.flake.modules.darwin.autoinputswitch ];

  flake.modules.darwin.autoinputswitch =
    { lib, config, ... }:
    let
      inherit (config.shelken.tools.autoinputswitch) app;
    in
    {
      options.shelken.tools.autoinputswitch.app = lib.mkOption {
        type = lib.types.enum [
          "typeswitch"
          "inputsourcepro"
        ];
        default = "typeswitch";
        description = "选择使用哪个自动输入法切换软件";
      };

      config = lib.mkMerge [
        (lib.mkIf (app == "typeswitch") {
          homebrew.casks = [ "shelken/tap/typeswitch" ];

          launchd.user.agents.autoinputswitch = {
            command = ''"/Applications/TypeSwitch.app/Contents/MacOS/TypeSwitch"'';
            serviceConfig.RunAtLoad = true;
          };
        })
        (lib.mkIf (app == "inputsourcepro") {
          homebrew.casks = [ "shelken/tap/input-source-pro-beta" ];

          system.defaults.CustomUserPreferences."space.ooooo.Input-Source-Pro.Beta" = {
            isRestorePreviouslyUsedInputSource = false;
            isActiveWhenSwitchApp = false;
          };
        })
      ];
    };

  flake.modules.homeManager.autoinputswitch =
    { lib, osConfig, ... }:
    let
      inherit (osConfig.shelken.tools.autoinputswitch) app;
      appRules =
        let
          fixed = id: {
            fixed = {
              inputMethodId = id;
            };
          };
          none = {
            none = { };
          };

          chinese = fixed "im.rime.inputmethod.Squirrel.Hans";
          english = fixed "com.apple.keylayout.ABC";
        in
        {
          "com.apple.Spotlight" = english;
          "com.microsoft.VSCode" = english;
          "dev.zed.Zed" = english;
          "dev.zed.Zed-Preview" = english;
          "com.conductor.app" = english;
          "com.apple.dt.Xcode" = english;
          "net.kovidgoyal.kitty" = english;
          "tv.parsec.www" = english;
          "com.google.Chrome" = english;
          "net.imput.helium" = english;
          "com.apple.Notes" = chinese;
          "com.tencent.xinWeChat" = chinese;
          "md.obsidian" = chinese;
          "ru.keepcoder.Telegram" = chinese;
          "com.kangfenmao.CherryStudio" = chinese;
          "com.openai.chat" = chinese;
          "com.anthropic.claudefordesktop" = chinese;
          "com.apple.MobileSMS" = chinese;
          "com.yetone.alma" = chinese;
          "com.apple.ScreenSharing" = none;
          "com.apple.finder" = none;
          "com.apple.Safari" = none;
          "com.apple.systempreferences" = none;
        };
      desiredJSON = builtins.toJSON appRules;
    in
    lib.mkMerge [
      (lib.mkIf (app == "typeswitch") {
        home.activation.typeswitchRules = ''
          file="$HOME/Library/Application Support/top.ygsgdbd.TypeSwitch/app-rules.json"
          if [ -f "$file" ]; then
            now=$(( $(date +%s) - 978307200 ))
            jq --argjson desired '${desiredJSON}' --argjson now "$now" '
              .rules = (.rules // {}) |
              reduce ($desired | to_entries[]) as $e (.;
                .rules[$e.key] |= (
                  (. // {}) *
                  {
                    bundleId: $e.key,
                    lastKnownName: (.lastKnownName // "Unknown"),
                    createdAt: (.createdAt // $now),
                    updatedAt: $now
                  }
                  | .strategy = $e.value
                )
              )
            ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
          fi
        '';
      })
      (lib.mkIf (app == "inputsourcepro") {
        home.file.".config/inputsourcepro/config.json".text =
          let
            fixedRules = lib.filterAttrs (_: v: v ? fixed) appRules;
            inputsourceproRules = builtins.mapAttrs (_: v: v.fixed.inputMethodId) fixedRules;
          in
          builtins.toJSON inputsourceproRules;
      })
    ];
}
