{
  mylib,
  config,
  lib,
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
    programs.bash.initExtra = shellInit;
    programs.zsh.initContent = shellInit;
  };
}
