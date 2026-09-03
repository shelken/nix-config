{
  mylib,
  config,
  lib,
  pkgs,
  sops-nix,
  ...
}:
let
  inherit (mylib) mkBoolOpt;
  inherit (lib) mkIf;
  cfg = config.shelken.secrets;

  # 环境变量 -> secret 相对路径的映射表
  # 统一在这一处声明，自动驱动：
  # 1. sops secrets 的解密注册
  # 2. 交互式 shell (zsh/bash) 的安全环境变量加载（直接使用 sops.secrets.<name>.path）
  secretEnvMap = {
    GH_TOKEN = "github/cli-token";
    GITHUB_TOKEN = "github/cli-token";
    HOMEBREW_GITHUB_API_TOKEN = "github/cli-token";
    CONTEXT7_API_KEY = "context7/api-key";
    DEEPSEEK_API_KEY = "deepseek/api-key";
    DASHSCOPE_API_KEY = "dashscope/api-key";
    GROQ_API_KEY = "groq/api-key";
    MODELSCOPE_API_KEY = "modelscope/api-key";
  };

  # 提取所有需要解密的 secret key 列表（去重）
  enabledSecrets = lib.unique (lib.attrValues secretEnvMap);

  # 直接通过 sops-nix 导出的 .path 属性注入环境变量
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

    # 2. 仅在运行目标命令时按需注入 ~/.specific.zsh，主终端默认完全不加载
    SPECIFIC_ZSH="$HOME/.specific.zsh"
    if [[ -s "$SPECIFIC_ZSH" ]]; then
      source "$SPECIFIC_ZSH"
    fi

    # 3. 仅在 SEC_RUN_VERBOSE 环境变量存在时回显注入清单（输出至 stderr，不污染管道）
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
      echo "  sec-env add <KEY> [VALUE]  # 增加/更新变量（未提供 VALUE 时安全交互式输入）"
      echo "  sec-env del <KEY>          # 删除变量"
      echo "  sec-env list               # 列出当前配置的所有变量名（只输出 Key，不泄露值）"
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
    enable = mkBoolOpt false "Whether or not use secrets";
  };
  config = mkIf cfg.enable {
    sops.secrets = mylib.mkSopsSecrets enabledSecrets;

    home.packages = [
      secRun
      secEnv
    ];
  };
}
