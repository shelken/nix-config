{
  mylib,
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (mylib) mkBoolOpt;
  inherit (lib) mkIf;
  cfg = config.shelken.infisical;

  # 项目 ID 只是资源标识符（等价于仓库名）
  projectId = "a3590f21-2f07-4972-b74d-62cf80154383";
in
{
  options.shelken.infisical = {
    enable = mkBoolOpt false "Whether or not to use Infisical CLI";
  };

  config = mkIf cfg.enable {
    home.packages = [ pkgs.infisical ];

    # CLI 的项目解析顺序: --projectId > INFISICAL_PROJECT_ID > .infisical.json
    # 用环境变量钉死项目, 避免其默认在 cwd 找 .infisical.json 的目录导向行为
    home.sessionVariables = {
      INFISICAL_PROJECT_ID = projectId;
      INFISICAL_DISABLE_UPDATE_CHECK = "true";
    };
  };
}
