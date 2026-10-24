# secrets：age 密钥能力（主机属性）与 sops-nix 用户态模块
# 系统侧选项在此声明，值由 hosts/<host>/default.nix 设置；
# HM 侧经 osConfig 只读同名选项
# 所有主机都可能有 age 密钥 → 两个 core 都导入；开关仍由主机设置
{ config, ... }:
{
  flake.modules.darwin.core.imports = [ config.flake.modules.darwin.secrets ];
  flake.modules.nixos.core.imports = [ config.flake.modules.nixos.secrets ];

  flake.modules.darwin.secrets =
    { lib, ... }:
    {
      options.shelken.secrets.enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether or not this host holds age secrets";
      };
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
      sops-nix,
      osConfig,
      ...
    }:
    let
      inherit (lib) mkIf;
      cfg = config.shelken.secrets;

      # ─── 凭据基座与覆盖层 ───
      # 基座：仓库内声明的 op:// 引用映射，注入文件只含引用不含明文，可安全进 nix store
      opSecretMap = {
        APIM_API_KEY = "Personal/APIM_API_KEY";
        BRAVE_API_KEY = "Personal/BRAVE_API_KEY";
        BRAVE_SEARCH_API_KEY = "Personal/BRAVE_SEARCH_API_KEY";
        BWS_ACCESS_TOKEN = "Personal/BWS_ACCESS_TOKEN";
        COMMANDCODE_API_KEY = "Personal/COMMANDCODE_API_KEY";
        CONTEXT_API_KEY = "Personal/CONTEXT_API_KEY";
        CPA_PI_API_KEY = "Personal/CPA_PI_API_KEY";
        CPA_TOKEN = "Personal/CPA_TOKEN";
        DEEPSEEK_API_KEY = "Personal/DEEPSEEK_API_KEY";
        EXA_API_KEY = "Personal/EXA_API_KEY";
        FIRECRAWL_API_KEY = "Personal/FIRECRAWL_API_KEY";
        MNEMOPI_EMBEDDING_API_KEY = "Personal/MNEMOPI_EMBEDDING_API_KEY";
        MODELSCOPE_API_KEY = "Personal/MODELSCOPE_API_KEY";
        MODELSCOPE_API_TOKEN = "Personal/MODELSCOPE_API_TOKEN";
        OMLX_API_KEY = "Personal/OMLX_API_KEY";
        OPENCODE_API_KEY = "Personal/OPENCODE_API_KEY";
        SANDVAULT_ARGS = "Personal/SANDVAULT_ARGS";
        WX_PI_API_KEY = "Personal/WX_PI_API_KEY";
      };

      # 基座 env 文件：VAR=op://<vault>/<item>/credential，只含引用不含明文
      opEnvBase = pkgs.writeText "op-secrets.env" (
        lib.concatStringsSep "\n" (
          lib.mapAttrsToList (var: ref: "${var}=op://${ref}/credential") opSecretMap
        )
      );

      secretEnvMap = {
        GITHUB_TOKEN = "github/cli-token"; # 目前task依赖
      };

      enabledSecrets = lib.unique (lib.attrValues secretEnvMap);

      shellInit = lib.concatStringsSep "\n" (
        lib.mapAttrsToList (var: secret: ''
          if [[ -r "${config.sops.secrets."${secret}".path}" ]]; then
            export ${var}="$(<"${config.sops.secrets."${secret}".path}")"
          fi
        '') secretEnvMap
      );
      secRun = pkgs.writeScriptBin "sec-run" ''
        #!${pkgs.zsh}/bin/zsh
        if (( $# == 0 )); then
          echo "Usage: sec-run <command> [args...]" >&2
          exit 1
        fi

        typeset -a _before_vars
        if [[ -n "''${SEC_RUN_VERBOSE:-}" ]]; then
          _before_vars=( ''${(k)parameters[(R)*export*]} )
        fi

        # 1. 注入 sops-nix 凭据
        ${shellInit}

        # 2. op CLI 可用时经 op run 解析 op:// 引用：仓库基座在前、specific.zsh 覆盖层在后（同
        # 名变量后者覆盖，# 注释临时停用，明文回退兼容）；无 op 的机器跳过整层
        SPECIFIC_ZSH="$HOME/.specific.zsh"
        if command -v op >/dev/null 2>&1; then
          typeset -a _op_env_files
          _op_env_files=( --env-file="${opEnvBase}" )
          if [[ -s "$SPECIFIC_ZSH" ]]; then
            _op_env_files+=( --env-file="$SPECIFIC_ZSH" )
          fi
          exec op run "''${_op_env_files[@]}" -- "$@"
        fi

        # 3. 无 op 回退：仅 source specific.zsh（明文语法与 sec-env 写入格式一致）
        if [[ -s "$SPECIFIC_ZSH" ]]; then
          source "$SPECIFIC_ZSH"
        fi

        # 4. 仅在 SEC_RUN_VERBOSE 存在时回显注入清单（stderr，不污染管道）
        if [[ -n "''${SEC_RUN_VERBOSE:-}" ]]; then
          typeset -a _after_vars _new_vars
          _after_vars=( ''${(k)parameters[(R)*export*]} )
          _new_vars=( ''${(ou)''${_after_vars:|_before_vars}} )
          if (( ''${#_new_vars} > 0 )); then
            print -u2 -- "🔐 [sec-run] 注入环境变量 (''${#_new_vars} 个): ''${(j:, :)_new_vars}"
          fi
        fi

        exec "$@"
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
            printf "export %s=%s\n" "$KEY" "''${(q)VALUE}" >> "$TMP_OUT"
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
        sops-nix.homeManagerModules.sops
      ];
      options.shelken.secrets = {
        # 主机属性：只在 hosts/<host>/default.nix 声明，HM 侧只读
        enable = lib.mkOption {
          type = lib.types.bool;
          default = osConfig.shelken.secrets.enable;
          readOnly = true;
          description = "主机是否持有 age 密钥（来自 osConfig.shelken.secrets.enable）";
        };
      };
      config = mkIf cfg.enable {
        # ─── 统一明确的 Age 解密密钥 ───
        sops.age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
        home.sessionVariables.SOPS_AGE_KEY_FILE = config.sops.age.keyFile;

        # ─── 统一凭据定义 ───
        sops.secrets = (mylib.mkSopsSecrets enabledSecrets) // {
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
}
