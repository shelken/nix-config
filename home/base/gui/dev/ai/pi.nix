{
  config,
  lib,
  pkgs,
  ...
}:
let
  aiCfg = config.shelken.dev.ai;
  home = config.home.homeDirectory;

  registry = {
    baseSettings = {
      defaultModel = "deepseek-v4-flash";
      defaultProvider = "opencode-go";
      defaultThinkingLevel = "high";
      hideThinkingBlock = false;
      npmCommand = [ "bun" ];
      "observational-memory" = {
        compactAfterTokensMode = "calibrated";
        compactAfterTokens = 250000;
        model = {
          id = "deepseek-v4-flash";
          provider = "opencode-go";
          thinking = "high";
        };
      };
      powerline = {
        welcome = false;
        customItems = [
          {
            id = "thinking-steps";
            statusKey = "thinking-steps";
            excludeFromExtensionStatuses = true;
          }
        ];
        disabledSegments = [ "custom:thinking-steps" ];
        preset = "default";
        fixedEditor = true;
      };
      powerlineShortcuts = {
        jumpChatBottom = null;
        jumpPreviousUserMessage = null;
        jumpNextUserMessage = null;
        jumpPreviousLlmMessage = null;
        jumpNextLlmMessage = null;
        cutEditor = null;
      };
      quietStartup = false;
      terminal = {
        showTerminalProgress = true;
        clearOnShrink = false;
      };
      theme = "catppuccin-macchiato";
      transport = "auto";
      tuiMode = "fullscreen";
      fullscreenScrollbar = "auto";
    };

    remotePackages = [
      "npm:pi-execution-time"
      "git:github.com/otahontas/pi-coding-agent-catppuccin"
      "npm:pi-powerline-footer"
      "npm:pi-jingle"
      "npm:pi-token-speed"
      "npm:@tifan/pi-handoff"
      "npm:@tifan/pi-preferred-thinking"
      "npm:@tifan/pi-recap"
      "npm:@tifan/pi-titlebar-spinner"
      "npm:@tifan/pi-rename"
      "npm:pi-vision-handoff"
      "npm:pi-rewind"
      "-git:github.com/shelken/pi-extensions"
      "npm:@juicesharp/rpiv-todo"
      "npm:pi-caveman"
      "npm:@ff-labs/pi-fff"
      "npm:pi-intercom"
      "npm:pi-subdir-context"
      "npm:@juicesharp/rpiv-web-tools"
      {
        source = "git:github.com/DietrichGebert/ponytail";
        skills = [
          "-skills/ponytail-debt/SKILL.md"
          "-skills/ponytail-gain/SKILL.md"
          "-skills/ponytail-help/SKILL.md"
          "-skills/ponytail-audit/SKILL.md"
        ];
      }
    ];

    localExtensions = [
      "${home}/Code/active/pi-zen-probe"
      "${home}/Code/active/pi-balance"
      "${home}/Code/active/pi-context-prune"
      "${home}/Code/active/pi-extensions/extensions/pi-auto-model-prompts"
      "${home}/Code/active/pi-extensions/extensions/pi-dynamic-models"
      "${home}/Code/active/pi-extensions/extensions/pi-guard"
      "${home}/Code/active/pi-extensions/extensions/pi-inline-skills"
      "${home}/Code/active/pi-extensions/extensions/pi-co-authored-by"
      "${home}/Code/active/pi-extensions/extensions/pi-command-history"
      "${home}/Code/active/pi-extensions/extensions/simple-plannotator"
      "${home}/Code/active/pi-extensions/extensions/copy-cut"
      "${home}/Code/active/pi-zed-provider"
      "-${home}/Code/active/pi-codebuddy-provider"
      "${home}/Code/active/pi-qwenwork-provider"
      "${home}/Code/active/pi-trae-provider"
    ];

    subagentConfig = {
      "//" = "子代理配置。spawn-subagent 每次启动读取本文件。exclude 黑名单规范：只写插件短名。";
      exclude = [
        "pi-context-prune"
        "rpiv-todo"
        "pi-observational-memory"
        "pi-recap"
      ];
      presets = {
        explore = {
          model = "openai-codex/gpt-5.6-luna";
          thinking = "max";
          tools = "read,bash,grep,find,ls,ffgrep,fffind,web_search,web_fetch,intercom";
        };
        general-purpose = {
          model = "openai-codex/gpt-5.6-luna";
          thinking = "max";
          tools = "read,bash,edit,write,grep,find,ls,ffgrep,fffind,web_search,web_fetch,intercom";
        };
        general-purpose-review = {
          model = "openai-codex/gpt-5.6-sol";
          thinking = "medium";
          tools = "read,bash,edit,write,grep,find,ls,ffgrep,fffind,intercom";
        };
        reviewer = {
          model = "openai-codex/gpt-5.6-sol";
          thinking = "medium";
          tools = "read,bash,grep,find,ls,ffgrep,fffind,intercom";
        };
      };
    };
  };

  hostSettings = registry.baseSettings // {
    packages = registry.remotePackages ++ registry.localExtensions;
  };

  hostSettingsFile = pkgs.writeText "pi-settings.json" (builtins.toJSON hostSettings);
  subagentConfigFile = pkgs.writeText "pi-subagent-config.json" (
    builtins.toJSON registry.subagentConfig
  );

  ponytailDir = "${config.home.homeDirectory}/nix-config/home/base/gui/dev/ai/ponytail";
  shellInit = ''
    # for extension pi-powerline-footer
    export POWERLINE_NERD_FONTS=1
    # for pi-fff
    export FFF_ENABLE_HOME_SCAN=0
    # for sandvault native install default
    export SANDVAULT_ARGS="--native-install"
  '';
in
{
  options.shelken.dev.ai.pi = {
    baseSettings = lib.mkOption {
      type = lib.types.attrs;
      default = registry.baseSettings;
      description = "Pi base settings shared across host and sandvault.";
      readOnly = true;
    };
    remotePackages = lib.mkOption {
      type = lib.types.listOf (lib.types.either lib.types.str lib.types.attrs);
      default = registry.remotePackages;
      description = "Declared remote npm/git packages.";
      readOnly = true;
    };
    subagentConfig = lib.mkOption {
      type = lib.types.attrs;
      default = registry.subagentConfig;
      description = "Unified subagent exclude and preset configuration.";
      readOnly = true;
    };
  };

  config = lib.mkIf aiCfg.enable {
    home.packages = with pkgs; [
      mermaid-cli # for npm:pi-markdown-preview
    ];

    # ponytail 扩展配置: 隐藏状态栏显示, 保留规则注入
    home.file.".config/ponytail/config.json" = {
      source = config.lib.file.mkOutOfStoreSymlink "${ponytailDir}/config.json";
      force = true;
    };

    shelken.backup.app.pi = [
      "${config.home.homeDirectory}/.pi"
    ];

    programs.zsh.initContent = shellInit;

    home.activation.writePiSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      mkdir -p ${lib.escapeShellArg "${home}/.pi/agent"}
      install -Dm644 ${lib.escapeShellArg hostSettingsFile} ${lib.escapeShellArg "${home}/.pi/agent/settings.json"}
    '';

    home.activation.writePiSubagentConfig = lib.hm.dag.entryAfter [ "writePiSettings" ] ''
      install -Dm644 ${lib.escapeShellArg subagentConfigFile} ${lib.escapeShellArg "${home}/.pi/agent/subagent-config.json"}
    '';
  };
}
