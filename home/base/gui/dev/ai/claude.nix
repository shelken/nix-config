{
  lib,
  config,
  pkgs,
  mylib,
  ...
}:
let
  cfg = config.shelken.dev.ai;
  secretsEnabled = config.shelken.secrets.enable;

  # MCP 配置文件路径
  mcpConfigPath = "${config.xdg.configHome}/mcp/mcp.json";

  # 创建 claude wrapper script（注入 --mcp-config）
  claudeWrapper = pkgs.writeShellScriptBin "claude" ''
    REAL_CLAUDE="/opt/homebrew/bin/claude"
    if [ ! -x "$REAL_CLAUDE" ]; then
      echo "Error: Claude Code not found at $REAL_CLAUDE" >&2
      exit 1
    fi

    if [ -f "${mcpConfigPath}" ]; then
      exec "$REAL_CLAUDE" --mcp-config "${mcpConfigPath}" "$@"
    else
      exec "$REAL_CLAUDE" "$@"
    fi
  '';

  # ============ Provider 定义（代理/认证方式）============
  providers = {
    # 自建代理服务
    cli-proxy-api = {
      needsSecrets = true;
      secrets = {
        "main-domain" = mylib.mkDefaultSecret { key = "main-domain"; };
        "cli-proxy-api/api-key" = mylib.mkDefaultSecret { key = "cli-proxy-api/api-key"; };
      };
      # shell 环境变量导出
      shellInit = ''
        # Claude Code API 配置（从 sops secrets 读取）
        export ANTHROPIC_BASE_URL="https://cli-proxy-api.$(cat ${config.sops.secrets."main-domain".path})"
        export ANTHROPIC_AUTH_TOKEN="$(cat ${config.sops.secrets."cli-proxy-api/api-key".path})"
      '';
    };
    anti-tools = {
      needsSecrets = true;
      secrets = {
      };
      # shell 环境变量导出
      shellInit = ''
        export ANTHROPIC_BASE_URL="http://127.0.0.1:8045"
        export ANTHROPIC_AUTH_TOKEN="x"
      '';
    };
  };

  # ============ Preset 定义（provider + 模型配置）============
  envPresets = {
    # 自建代理 + Gemini Claude 模型
    cpa-gemini-claude = {
      provider = "cli-proxy-api";
      models = {
        ANTHROPIC_DEFAULT_HAIKU_MODEL = "qwen3-coder-plus";
        ANTHROPIC_DEFAULT_OPUS_MODEL = "claude-opus-4-5-thinking";
        ANTHROPIC_DEFAULT_SONNET_MODEL = "claude-sonnet-4-5";
        ANTHROPIC_MODEL = "claude-opus-4-5-thinking";
        ANTHROPIC_REASONING_MODEL = "claude-opus-4-5-thinking";
      };
    };
    anti-tools = {
      provider = "anti-tools";
      models = {
        ANTHROPIC_DEFAULT_HAIKU_MODEL = "gemini-2.5-flash-lite";
        ANTHROPIC_DEFAULT_OPUS_MODEL = "claude-opus-4-5-thinking";
        ANTHROPIC_DEFAULT_SONNET_MODEL = "claude-sonnet-4-5";
        ANTHROPIC_MODEL = "claude-opus-4-5-thinking";
        ANTHROPIC_REASONING_MODEL = "claude-opus-4-5-thinking";
      };
    };
    cpa-gemini = {
      provider = "cli-proxy-api";
      models = {
        ANTHROPIC_DEFAULT_HAIKU_MODEL = "gemini-3-flash-preview";
        ANTHROPIC_DEFAULT_OPUS_MODEL = "gemini-3-pro-preview";
        ANTHROPIC_DEFAULT_SONNET_MODEL = "gemini-3-pro-preview";
        ANTHROPIC_MODEL = "gemini-3-pro-preview";
        ANTHROPIC_REASONING_MODEL = "gemini-3-pro-preview";
      };
    };
    cpa-codex = {
      provider = "cli-proxy-api";
      models = {
        # gpt-5
        # gpt-5.1-codex
        # gpt-5.2
        # gpt-5.1
        # gpt-5.1-codex-mini
        # gpt-5.1-codex-max
        # gpt-oss-120b-medium
        # gpt-5-codex
        # gpt-5-codex-mini
        # gpt-5.2-codex
        ANTHROPIC_DEFAULT_HAIKU_MODEL = "gpt-5.1-codex-mini";
        ANTHROPIC_DEFAULT_OPUS_MODEL = "gpt-5.2-codex(high)";
        ANTHROPIC_DEFAULT_SONNET_MODEL = "gpt-5.1(high)";
        ANTHROPIC_MODEL = "gpt-5.2-codex(high)";
        ANTHROPIC_REASONING_MODEL = "gpt-5.2-codex(high)";
      };
    };
  };

  # ============ 计算当前选择的配置 ============
  selectedPreset = if cfg.claudePreset != null then envPresets.${cfg.claudePreset} else null;
  selectedProvider = if selectedPreset != null then providers.${selectedPreset.provider} else null;

  # 判断是否需要启用 secrets
  useSecrets = selectedProvider != null && selectedProvider.needsSecrets && secretsEnabled;

  # env 配置只包含模型（敏感字段通过 shell 环境变量提供）
  selectedEnv = if selectedPreset != null then selectedPreset.models else { };

  # 基础 settings 配置
  baseSettings = {
    "$schema" = "https://json.schemastore.org/claude-code-settings.json";
    includeCoAuthoredBy = false;
    permissions = {
      allow = [
        "Bash(mkdir:*)"
        "Bash(grep:*)"
        "Bash(find:*)"
        "Bash(rg:*)"
        "Bash(ls:*)"
        "Bash(git --no-pager status:*)"
        "Bash(git --no-pager diff:*)"
        "Bash(git --no-pager log:*)"
        "Bash(git --no-pager show:*)"
        "Bash(git rev-parse:*)"
        "mcp__context7"
        "mcp__github"
        "Skill(superpowers:*)"
        "Skill(openspec:*)"
        "Skill(everything-claude-code:*)"
        "Bash(awk:*)"
      ];
    };
    hooks = {
      Notification = [
        {
          matcher = "";
          hooks = [
            {
              type = "command";
              command = "afplay /System/Library/Sounds/Funk.aiff";
            }
          ];
        }
      ];
      Stop = [
        {
          matcher = "";
          hooks = [
            {
              type = "command";
              command = "afplay /System/Library/Sounds/Glass.aiff";
            }
          ];
        }
      ];
    };
    extraKnownMarketplaces = {
      "everything-claude-code" = {
        "source" = {
          "source" = "github";
          "repo" = "affaan-m/everything-claude-code";
        };
      };
      "planning-with-files" = {
        "source" = {
          "source" = "github";
          "repo" = "OthmanAdi/planning-with-files";
        };
      };
    };
    enabledPlugins = {
      "everything-claude-code@everything-claude-code" = true;
      "planning-with-files@planning-with-files" = true;
      "code-simplifier@claude-plugins-official" = true;

      "superpowers-developing-for-claude-code@superpowers-marketplace" = false;
      "superpowers-lab@superpowers-marketplace" = false;
      "superpowers@superpowers-marketplace" = false;
    };
  };
in
{
  options.shelken.dev.ai.claudePreset = lib.mkOption {
    type = lib.types.nullOr (lib.types.enum (builtins.attrNames envPresets));
    default = null;
    description = ''
      Claude Code 预设配置集：
      - cpa-gemini-claude: 自建代理 + Gemini Claude 模型（需要 secrets）
      - anti-tools: Antigravity Tools
      - null: 不注入 env 配置
    '';
    example = "cpa-gemini-claude";
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      # 基础配置（始终生效）
      {
        programs.claude-code = {
          enable = true;
          package = null; # 使用 Homebrew 安装的 claude-code
          settings = baseSettings // {
            env = selectedEnv;
          };
        };

        programs.bun.enable = true;

        # 添加 claude wrapper 到 PATH（优先级高于 Homebrew）
        home.packages = lib.mkIf config.programs.mcp.enable [ claudeWrapper ];
      }

      # secrets 相关配置（仅在需要时生效）
      (lib.mkIf useSecrets {
        sops.secrets = selectedProvider.secrets;
        programs.bash.initExtra = selectedProvider.shellInit;
        programs.zsh.initContent = selectedProvider.shellInit;
      })
    ]
  );
}
