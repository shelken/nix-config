# singbox-config：把 mac / ios / router 三份 sbtools 配置声明式管起来
#
# 私密值在模板里只以 1Password 引用（`{{ op://… }}`）出现，运行时由 sec-run 填充；
# 生成的 yaml 只落在临时目录，encode 完即删。仓库与 nix store 里都没有明文。
#
# 与 mise.nix 同挂 gui：sbtools 由 mise 提供，填充动作依赖 secrets 功能里的 sec-run
{
  config,
  ...
}:
{
  flake.modules.darwin.gui.imports = [ config.flake.modules.darwin.singbox-config ];
  flake.modules.nixos.gui.imports = [ config.flake.modules.nixos.singbox-config ];

  # singbox-config：填充模板 → encode 成订阅 URL；逻辑在 singbox-config.sh
  flake.modules.homeManager.singbox-config =
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
        runtimeEnv = {
          TEMPLATES_DIR = "${./templates}";
          MAIN_DOMAIN_FILE = config.sops.secrets.singbox-main-domain.path;
        };
        text = builtins.readFile ./singbox-config.sh;
      };
    in
    {
      config = lib.mkIf config.shelken.secrets.enable {
        # 订阅服务地址：sops 里只存裸域名，scheme 在脚本里拼（同 backup/kopia 的用法）
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
    };
}
