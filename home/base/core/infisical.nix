{
  mylib,
  config,
  lib,
  ...
}:
let
  inherit (mylib) mkBoolOpt;
  inherit (lib) mkIf;
  cfg = config.shelken.infisical;

  # 项目 ID 只是资源标识符（等价于仓库名），非机密，可直接入库
  projectId = "a3590f21-2f07-4972-b74d-62cf80154383";
in
{
  options.shelken.infisical = {
    enable = mkBoolOpt false "Whether or not to use Infisical CLI";
  };

  config = mkIf cfg.enable {
    # CLI 由 mise 托管(latest, 0.43.x), nix 侧只负责声明配置
    programs.mise.globalConfig.tools.infisical = "latest";

    # 项目解析顺序(v0.43.88+): --projectId > INFISICAL_PROJECT_ID > .infisical.json
    # 环境变量钉死项目, 避免其默认在 cwd 找 .infisical.json 的目录导向行为
    home.sessionVariables = {
      INFISICAL_PROJECT_ID = projectId;
      INFISICAL_DISABLE_UPDATE_CHECK = "true";
    };
  };
}
