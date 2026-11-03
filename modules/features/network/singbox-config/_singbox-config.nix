# singbox-config：填充模板 → 校验 → encode 成订阅 URL
#
# 逻辑在 singbox-config.sh，这里只注入两个路径。用 replaceStrings 而不是
# pkgs.replaceVars：后者要 readFile 一个 store 路径，会引入 IFD。
{
  config,
  lib,
  mylib,
  pkgs,
  ...
}:
let
  script = pkgs.writeShellApplication {
    name = "singbox-config";
    runtimeInputs = [ pkgs.coreutils ];
    text =
      lib.replaceStrings
        [ "@templatesDir@" "@mainDomainFile@" ]
        [ "${./templates}" "${config.sops.secrets.singbox-main-domain.path}" ]
        (builtins.readFile ./singbox-config.sh);
  };
in
{
  config = lib.mkIf config.shelken.secrets.enable {
    # 订阅服务地址：sops 里只存裸域名，scheme 在脚本里拼（同 backup/_kopia 的用法）
    sops.secrets.singbox-main-domain = mylib.mkDefaultSecret { key = "main-domain"; };

    # sbtools 由 mise 提供；只在用得上它的主机上声明，不占全局工具表
    programs.mise.globalConfig.tools = {
      "github:shelken/proxy" = {
        version = "latest";
        matching = "sbtools";
        minimum_release_age = "0h";
      };
    };

    home.packages = [ script ];
  };
}
