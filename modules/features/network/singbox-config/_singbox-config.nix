# singbox-config：填充模板 → 校验 → encode 成订阅 URL
#
# 逻辑在 singbox-config.sh，这里注入两个路径和渲染好的 router 模板。用 replaceStrings
# 而不是 pkgs.replaceVars：后者要 readFile 一个 store 路径，会引入 IFD。
{
  config,
  lib,
  mylib,
  myvars,
  pkgs,
  ...
}:
let
  # 旁路由白名单：名单内设备的透明 DNS 与流量走盒子，名单外由内核直接转发。
  # 地址取 vars/networking.nix 的登记；没登记的设备写裸 IP（统一补 /32）
  lan = myvars.networking.hostAddress;
  whitelistCidrs = map (ip: "${ip}/32") [
    lan."sakamoto-k8s".address
    lan."yuuko-k8s".address
    lan."homelab-1".address
    lan."pve".address
    lan."yuuko".address
    lan."sakamoto".address
    "192.168.6.125" # quest
  ];

  # 模板里两处 source_ip_cidr 共用占位符 @whitelistCidrs@，渲染成 JSON 数组
  routerTemplate = pkgs.writeText "router.yaml" (
    lib.replaceStrings
      [ "@whitelistCidrs@" ]
      [ (lib.concatMapStringsSep ", " (cidr: ''"${cidr}"'') whitelistCidrs) ]
      (builtins.readFile ./templates/router.yaml)
  );

  script = pkgs.writeShellApplication {
    name = "singbox-config";
    runtimeInputs = [ pkgs.coreutils ];
    text =
      lib.replaceStrings
        [ "@templatesDir@" "@mainDomainFile@" "@routerTemplate@" ]
        [
          "${./templates}"
          "${config.sops.secrets.singbox-main-domain.path}"
          "${routerTemplate}"
        ]
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
