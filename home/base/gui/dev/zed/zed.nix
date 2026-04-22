{
  config,
  lib,
  ...
}:
let
  snippetsSourcePath = "${config.home.homeDirectory}/nix-config/home/base/gui/dev/zed/snippets";
  snippetFiles = builtins.attrNames (
    lib.filterAttrs (name: type: type == "regular" && lib.strings.hasSuffix ".json" name) (
      builtins.readDir ./snippets
    )
  );
  snippetLinks = lib.listToAttrs (
    map (name: {
      name = ".config/zed/snippets/${name}";
      value = {
        source = config.lib.file.mkOutOfStoreSymlink "${snippetsSourcePath}/${name}";
        force = true;
      };
    }) snippetFiles
  );
in
{
  catppuccin.zed.enable = false;
  home.file = snippetLinks;
  programs.zed-editor = {
    enable = true;
    package = null; # homebrew
    mutableUserSettings = true;
    mutableUserKeymaps = true;
    # 注意：
    # 列表不要直接传入，会直接覆盖
    userSettings = {
      # Zed settings
      #
      # For information on how to configure Zed, see the Zed
      # documentation: https://zed.dev/docs/configuring-zed
      #
      # To see all of Zed's default settings without changing your
      # custom settings, run `zed: open default settings` from the
      # command palette (cmd-shift-p / ctrl-shift-p)

      completions = {
        words_min_length = 2;
      };

      language_models = {
        anthropic = {
          api_url = "https://cpa.ooooo.space";
        };

        openai = {
          api_url = "https://cpa.ooooo.space/v1";
          # available_models = [
          #   {
          #     name = "gpt-5.4";
          #     display_name = "GPT-5.4";
          #     max_tokens = 1000000;
          #     max_output_tokens = 128000;
          #     reasoning_effort = "high";
          #     capabilities = {
          #       chat_completions = false;
          #     };
          #   }
          # ];
        };

        openai_compatible = {
          # "kimi-code" = {
          #   api_url = "https://api.kimi.com/coding/v1";
          #   available_models = [
          #     {
          #       name = "kimi-for-coding";
          #       max_tokens = 262144;
          #       max_output_tokens = 32768;
          #       max_completion_tokens = 262144;
          #       capabilities = {
          #         tools = true;
          #         images = true;
          #         parallel_tool_calls = true;
          #         prompt_cache_key = true;
          #         chat_completions = true;
          #       };
          #     }
          #   ];
          # };

          "OpenCode Zen" = {
            api_url = "https://opencode.ai/zen/v1";
            # available_models = [
            #   {
            #     name = "minimax-m2.1-free";
            #     max_tokens = 204800;
            #     max_output_tokens = 32000;
            #     max_completion_tokens = 204800;
            #     capabilities = {
            #       tools = true;
            #       images = false;
            #       parallel_tool_calls = false;
            #       prompt_cache_key = false;
            #       chat_completions = true;
            #     };
            #   }
            #   {
            #     name = "minimax-m2.5-free";
            #     max_tokens = 204800;
            #     max_output_tokens = 32000;
            #     max_completion_tokens = 204800;
            #     capabilities = {
            #       tools = true;
            #       images = false;
            #       parallel_tool_calls = false;
            #       prompt_cache_key = false;
            #       chat_completions = true;
            #     };
            #   }
            # ];
          };
        };
      };

      agent = {
        play_sound_when_agent_done = "always";
        dock = "right";

        tool_permissions = {
          default = "allow";
        };

        # model_parameters = [
        #   # 代码生成/数学解题      0.0
        #   # 数据抽取/分析        1.0
        #   # 通用对话            1.3
        #   # 翻译                1.3
        #   # 创意类写作/诗歌创作  1.5
        #   # {
        #   #   provider = "deepseek";
        #   #   temperature = 0.0;
        #   # }
        # ];
      };

      git_panel = {
        tree_view = true;
        sort_by_path = false;
      };

      icon_theme = {
        mode = "system";
        light = "Catppuccin Macchiato";
        dark = "Catppuccin Macchiato";
      };

      # ssh_connections = [
      # ];

      ui_font_family = "JetBrainsMono Nerd Font Mono";
      buffer_font_family = "JetBrainsMono Nerd Font Mono";

      terminal = {
        font_size = 15.0;
      };

      telemetry = {
        diagnostics = false;
        metrics = false;
      };

      # proxy = "http://127.0.0.1:7890";

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
      ui_font_size = 18.0;
      buffer_font_size = 16.0;

      theme = {
        mode = "system";
        light = "Catppuccin Macchiato";
        dark = "Catppuccin Macchiato";
      };

      agent_servers = {
        "claude-acp" = {
          type = "registry";
          env = {
            CLAUDE_CODE_EXECUTABLE = "/opt/homebrew/bin/claude";
          };
        };

        # opencode = {
        #   type = "custom";
        #   command = "/opt/homebrew/bin/opencode";
        #   args = [ "acp" ];
        # };

        "codex-acp" = {
          default_config_options = {
            mode = "full-access";
          };
          type = "registry";
        };

        # kimi = {
        #   type = "custom";
        #   command = "kimi";
        #   args = [ "acp" ];
        #   env = { };
        # };
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
        "yaml-language-server" = {
          settings = {
            yaml = {
              schemas = {
                # 为特定的 YAML 文件类型指定 schema
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
        "docker-compose" = false; # https://github.com/zed-industries/zed/issues/12122#issuecomment-2613014716
        dockerfile = true;
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
          "cmd-1" = "project_panel::ToggleFocus";
          "cmd-2" = "git_panel::ToggleFocus";
          "cmd-3" = "terminal_panel::Toggle";
        };
      }
    ];
  };
}
