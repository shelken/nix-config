{
  pkgs,
  myvars,
  ...
}:
let
  themeName = myvars.catppuccin.displayName;
in
{
  catppuccin.zed.enable = false;
  # zed 的 nix 扩展不带 LSP 二进制, 从 PATH 取 nixd(依赖归属: 谁用谁声明)
  home.packages = [ pkgs.nixd ];
  home.shellAliases = {
    zed = "sec-run zed";
  };
  programs.zed-editor = {
    enable = true;
    package = null;
    mutableUserSettings = true;
    mutableUserKeymaps = true;
    userSettings = {

      file_scan_exclusions = [
        "..."
        "**/node_modules"
        "**/target"
        "**/dist"
        "**/coverage"
        "**/.next"
        "**/.turbo"
        "**/.venv"
        "**/__pycache__"
        "**/.pytest_cache"
        "**/.mypy_cache"
        "**/.ruff_cache"
        "**/.gradle"
        "**/.direnv"
        "**/agent/git"
        "**/agent/npm"
        "**/agent/sessions"
        "**/agent/cache"
        "**/agent/logs"
        "**/agent/tmp"
        "**/agent-subagent/sessions"
        "**/agent-subagent/cache-parent"
      ];

      completions = {
        words_min_length = 2;
      };
      agent = {
        play_sound_when_agent_done = "always";

        tool_permissions = {
          default = "allow";
        };

      };

      git_panel = {
        tree_view = true;
        sort_by = "path";
      };

      icon_theme = {
        mode = "system";
        light = themeName;
        dark = themeName;
      };

      ui_font_family = myvars.fontFamilies.cjkMonospace;
      buffer_font_family = myvars.fontFamilies.monospace;
      buffer_font_fallbacks = [ myvars.fontFamilies.cjkMonospace ];

      terminal = {
        font_family = myvars.fontFamilies.monospace;
        font_fallbacks = [ myvars.fontFamilies.cjkMonospace ];
        option_as_meta = true;
      };

      telemetry = {
        diagnostics = false;
        metrics = false;
      };

      git = {
        inline_blame = {
          enabled = true;
        };
      };

      base_keymap = "VSCode";

      status_bar = {
        "experimental.show" = true;
      };

      minimap = {
        show = "auto";
      };

      hover_popover_enabled = true;
      autosave = "on_focus_change";

      linked_edits = true;
      tab_size = 2;

      theme = {
        mode = "system";
        light = themeName;
        dark = themeName;
      };

      languages = {
        Nix = {
          formatter = {
            external = {
              command = "nixfmt";
              arguments = [ "--width=100" ];
            };
          };
          language_servers = [
            "nixd"
            "!nil"
          ];
        };

        "Shell Script" = {
          tab_size = 4;
        };

        TOML = {
          formatter = {
            external = {
              command = "taplo";
              arguments = [
                "format"
                "-"
              ];
            };
          };
        };

        YAML = {
          format_on_save = "off";
        };
      };

      lsp = {
        "nixd" = {
          settings = {
            eval.workers = 1;
          };
        };
        "yaml-language-server" = {
          settings = {
            yaml = {
              schemas = {
              };
              completion = true;
              hover = true;
              validate = true;
            };
          };
        };
      };

      auto_install_extensions = {
        ansible = true;
        basher = true;
        caddyfile = true;
        catppuccin = true;
        "catppuccin-icons" = true;
        "color-highlight" = true;
        csv = true;
        dockerfile = true;
        env = true;
        "git-firefly" = true;
        html = true;
        ini = true;
        json5 = true;
        just = true;
        log = true;
        lua = true;
        make = true;
        "markdown-oxide" = true;
        "mcp-server-context7" = true;
        "mcp-server-exa-search" = true;
        mermaid = true;
        nginx = true;
        nix = true;
        ruby = true;
        sql = true;
        swift = true;
        terraform = false;
        toml = true;
        wakatime = true;
        xml = true;
      };

      inlay_hints = {
        enabled = true;
        show_type_hints = true;
        show_parameter_hints = true;
        show_other_hints = true;
      };
    };

    userKeymaps = [
      {
        context = "AgentPanel";
        bindings = {
          "cmd-1" = "project_panel::ToggleFocus";
          "cmd-e" = "workspace::FocusCenterPane";
        };
      }
      {
        context = "Editor";
        bindings = {
          "cmd-g b" = "git::Blame";
          "ctrl-tab" = "editor::ShowCompletions";
        };
      }
      {
        context = "GitPanel";
        bindings = {
          "cmd-shift-k" = "git::Push";
        };
      }
      {
        context = "Workspace";
        bindings = {
          "cmd-`" = "agent::ToggleFocus";
          "cmd-1" = "project_panel::Toggle";
          "cmd-2" = "git_panel::Toggle";
          "cmd-3" = "terminal_panel::Toggle";
        };
      }
      {
        context = "Terminal";
        unbind = {
          "shift-up" = "terminal::ScrollLineUp";
        };
      }
      {
        context = "Terminal";
        unbind = {
          "shift-down" = "terminal::ScrollLineDown";
        };
      }
      {
        context = "Terminal";
        unbind = {
          "ctrl-r" = [
            "terminal::SendKeystroke"
            "ctrl-r"
          ];
        };
      }
      {
        context = "GitPanel";
        unbind = {
          "cmd-1" = "git_panel::ActivateChangesTab";
        };
      }
      {
        context = "GitPanel";
        unbind = {
          "cmd-2" = "git_panel::ActivateHistoryTab";
        };
      }
    ];
  };
}
