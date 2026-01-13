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
  };

  # ============ Preset 定义（provider + 模型配置）============
  envPresets = {
    # 自建代理 + Gemini Claude 模型
    cpa-gemini-claude = {
      provider = "cli-proxy-api";
      models = {
        ANTHROPIC_DEFAULT_HAIKU_MODEL = "deepseek-chat";
        ANTHROPIC_DEFAULT_OPUS_MODEL = "gemini-claude-opus-4-5-thinking";
        ANTHROPIC_DEFAULT_SONNET_MODEL = "gemini-3-pro-preview";
        ANTHROPIC_MODEL = "gemini-claude-opus-4-5-thinking";
        ANTHROPIC_REASONING_MODEL = "gemini-claude-opus-4-5-thinking";
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
    enabledPlugins = {
      "planning-with-files@planning-with-files" = false;
      "superpowers-developing-for-claude-code@superpowers-marketplace" = true;
      "superpowers-lab@superpowers-marketplace" = true;
      "superpowers@superpowers-marketplace" = true;
      "code-simplifier@claude-plugins-official" = true;
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
