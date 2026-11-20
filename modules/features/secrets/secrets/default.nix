{ config, ... }:
{
  flake.modules.darwin.core.imports = [ config.flake.modules.darwin.secrets ];
  flake.modules.homeManager.tui.imports = [ config.flake.modules.homeManager.secrets-cli ];
  flake.modules.nixos.core.imports = [ config.flake.modules.nixos.secrets ];

  flake.modules.darwin.secrets =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    {
      options.shelken.secrets.enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether or not this host holds age secrets";
      };

      config.environment.systemPackages = lib.mkIf config.shelken.secrets.enable [
        pkgs._1password-cli
      ];
    };

  flake.modules.nixos.secrets =
    { lib, ... }:
    {
      options.shelken.secrets.enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether or not this host holds age secrets";
      };
    };

  flake.modules.homeManager.secrets =
    {
      mylib,
      config,
      lib,
      pkgs,
      inputs,
      osConfig,
      ...
    }:
    let
      inherit (lib) mkIf;
      cfg = config.shelken.secrets;

      # 条目必须放在 Agent vault：sec-run 用的 service account 只能读它（1Password 不允许授权 Personal）
      opSecretMap = {
        BRAVE_API_KEY = "Agent/BRAVE_API_KEY";
        BRAVE_SEARCH_API_KEY = "Agent/BRAVE_SEARCH_API_KEY";
        CONTEXT_API_KEY = "Agent/CONTEXT_API_KEY";
        CPA_PI_API_KEY = "Agent/CPA_PI_API_KEY";
        MAGPIE_API_KEY = "Agent/MAGPIE_API_KEY";
        CPA_TOKEN = "Agent/CPA_TOKEN";
        DEEPSEEK_API_KEY = "Agent/DEEPSEEK_API_KEY";
        EXA_API_KEY = "Agent/EXA_API_KEY";
        FIRECRAWL_API_KEY = "Agent/FIRECRAWL_API_KEY";
        MNEMOPI_EMBEDDING_API_KEY = "Agent/MNEMOPI_EMBEDDING_API_KEY";
        MODELSCOPE_API_KEY = "Agent/MODELSCOPE_API_KEY";
        MODELSCOPE_API_TOKEN = "Agent/MODELSCOPE_API_TOKEN";
        OMLX_API_KEY = "Agent/OMLX_API_KEY";
      };

      opEnvBase = pkgs.writeText "op-secrets.env" (
        lib.concatStringsSep "\n" (
          lib.mapAttrsToList (var: ref: "${var}=op://${ref}/credential") opSecretMap
        )
        + "\n"
      );

      secretEnvMap = {
        AGENT_GITHUB_TOKEN = "github/agent-token";
      };

      enabledSecrets = lib.unique (lib.attrValues secretEnvMap);

      opTokenSecret = "op/service-account-token";
      opTokenFile = config.sops.secrets."${opTokenSecret}".path;

      shellInit = lib.concatStringsSep "\n" (
        lib.mapAttrsToList (var: secret: ''
          if [[ -r "${config.sops.secrets."${secret}".path}" ]]; then
            export ${var}="$(<"${config.sops.secrets."${secret}".path}")"
          fi
        '') secretEnvMap
      );
      # -f：不读启动文件。调用者环境里没有 __NIX_DARWIN_SET_ENVIRONMENT_DONE 时（hc 守护进程启动的子代理），
      # /etc/zshenv 会把 PATH 重置成系统默认，mise 装的目标命令就找不到了
      secRun = pkgs.writeScriptBin "sec-run" ''
        #!${pkgs.zsh}/bin/zsh -f
        ${shellInit}
        SEC_RUN_BASE=${opEnvBase}
        SEC_RUN_TOKEN_FILE=${opTokenFile}
        ${builtins.readFile ./sec-run.zsh}
      '';

      secEnv = pkgs.writeScriptBin "sec-env" ''
        #!${pkgs.zsh}/bin/zsh
        set -e

        SPECIFIC_FILE="''${SPECIFIC_ZSH:-$HOME/.specific.zsh}"

        usage() {
          echo "用法: sec-env <add|del|list> [参数...]"
          echo "  sec-env add <KEY> [VALUE]  # 增加/更新覆盖层变量；推荐 VALUE 用 op:// 引用"
          echo "                            # （临时覆盖基座值或切换备用账号时）"
          echo "  sec-env del <KEY>          # 删除变量"
          echo "  sec-env list               # 列出覆盖层变量名（只输出 Key，不泄露值）"
          echo ""
          echo "覆盖层文件: \$SPECIFIC_FILE（仅 sec-run 运行时经 op run 注入）"
          exit 1
        }

        case "''${1:-}" in
          add)
            KEY="''${2:-}"
            if [[ -z "$KEY" ]]; then
              echo "错误: 未提供变量名 (KEY)" >&2
              usage
            fi
            if [[ ! "$KEY" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
              echo "错误: 非法变量名 '$KEY'" >&2
              exit 1
            fi

            if (( $# >= 3 )); then
              VALUE="$3"
            else
              read -s -r "VALUE?输入 $KEY 的值: "
              echo ""
            fi

            if [[ -z "$VALUE" ]]; then
              echo "错误: 变量值不可为空" >&2
              exit 1
            fi

            touch "$SPECIFIC_FILE"
            TMP_OUT="$(mktemp)"
            awk -v k="$KEY" 'BEGIN { re = "^[[:space:]]*(export[[:space:]]+)?" k "=" } $0 !~ re { print }' "$SPECIFIC_FILE" > "$TMP_OUT"
            # dotenv 双引号格式：zsh source 与 op run 解析结果一致（(q) 转义只有
            # shell 认，op 会把反斜杠留在值里）。内部 " 与 \ 需转义。
            VALUE_ESC="''${VALUE//\\/\\\\}"
            VALUE_ESC="''${VALUE_ESC//\"/\\\"}"
            printf 'export %s="%s"\n' "$KEY" "$VALUE_ESC" >> "$TMP_OUT"
            mv "$TMP_OUT" "$SPECIFIC_FILE"
            chmod 600 "$SPECIFIC_FILE"
            echo "✅ 已保存: $KEY"
            ;;
          del|rm)
            KEY="''${2:-}"
            if [[ -z "$KEY" ]]; then
              echo "错误: 未提供要删除的变量名" >&2
              usage
            fi
            if [[ ! -f "$SPECIFIC_FILE" ]]; then
              echo "⚠️ 目标文件不存在: $SPECIFIC_FILE" >&2
              exit 1
            fi

            if ! grep -E "^[[:space:]]*(export[[:space:]]+)?$KEY=" "$SPECIFIC_FILE" >/dev/null 2>&1; then
              echo "⚠️ 未找到变量: $KEY" >&2
              exit 1
            fi

            TMP_OUT="$(mktemp)"
            awk -v k="$KEY" 'BEGIN { re = "^[[:space:]]*(export[[:space:]]+)?" k "=" } $0 !~ re { print }' "$SPECIFIC_FILE" > "$TMP_OUT"
            mv "$TMP_OUT" "$SPECIFIC_FILE"
            chmod 600 "$SPECIFIC_FILE"
            echo "🗑️ 已删除: $KEY"
            ;;
          list|ls)
            if [[ ! -s "$SPECIFIC_FILE" ]]; then
              echo "（$SPECIFIC_FILE 不存在或为空）"
              exit 0
            fi
            echo "=== $SPECIFIC_FILE 中的变量 ==="
            grep -E "^[[:space:]]*(export[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*=" "$SPECIFIC_FILE" | \
              sed -E 's/^[[:space:]]*(export[[:space:]]+)?//; s/=.*//' | sort -u
            ;;
          *)
            usage
            ;;
        esac
      '';
    in
    {
      imports = [
        inputs.sops-nix.homeManagerModules.sops
      ];
      options.shelken.secrets = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = osConfig.shelken.secrets.enable;
          readOnly = true;
          description = "主机是否持有 age 密钥（来自 osConfig.shelken.secrets.enable）";
        };
      };
      config = mkIf cfg.enable {
        sops.age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
        home.sessionVariables.SOPS_AGE_KEY_FILE = config.sops.age.keyFile;

        sops.secrets =
          (mylib.mkSopsSecrets (
            enabledSecrets
            ++ [
              opTokenSecret
              "github/cli-token"
            ]
          ))
          // {
            "wakatime/conf" = mylib.mkDefaultSecret {
              path = "${config.home.homeDirectory}/.wakatime.cfg";
            };
            "asciinema/install-id" = mylib.mkDefaultSecret {
              path = "${config.home.homeDirectory}/.config/asciinema/install-id";
            };
          };

        sops.templates."gh-hosts.yml" = {
          path = "${config.home.homeDirectory}/.config/gh/hosts.yml";
          content = ''
            github.com:
                user: ${config.home.username}
                oauth_token: ${config.sops.placeholder."github/cli-token"}
                git_protocol: ssh
          '';
          mode = "0600";
        };

        home.packages = [
          pkgs.gopass
          secRun
          secEnv
        ];
      };
    };

  flake.modules.homeManager.secrets-cli =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        age
        sops
        ssh-to-age
      ];
    };
}
