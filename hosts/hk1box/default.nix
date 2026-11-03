{
  self,
  myvars,
  secrets,
  ...
}:
#############################################################
#
#  hk1box：HK1 Box（S905X3 电视盒子）当单臂旁路由，只跑 sing-box
#
#  原先刷 ImmortalWrt（ophub 打包）；现在是普通 NixOS 主机，用 deploy-rs 推送
#  硬件与引导见 ./hardware.nix，eMMC 分区见 ./disk.nix，试机镜像见 ./image.nix
#  从 ImmortalWrt 切过来的步骤见 ./README.md
#
#  单臂：只有一个网口，客户端把网关指向这台；它把流量交给 sing-box，再从同一个网口发给主路由
#  地址：沿用 vars/networking.nix 里的登记（同一网段，网关是主路由）
#  sing-box 配置含节点凭据，整份放在 secrets 仓库的 sops 文件里，激活时解到 /etc/sing-box/
#
#############################################################
let
  inherit (myvars.networking) hostAddress prefixLength;
  gateway = hostAddress.router-mine.address;
in
{
  imports = [
    self.modules.nixos.server
    self.modules.nixos.sops
    ./hardware.nix
    ./disk.nix
    ./image.nix
  ];

  networking = {
    hostName = "hk1box";
    # 只有一个网口，沿用 ImmortalWrt 时的 eth0
    usePredictableInterfaceNames = false;
    useDHCP = false;
    interfaces.eth0.ipv4.addresses = [
      {
        inherit (hostAddress.hk1box) address;
        inherit prefixLength;
      }
    ];
    defaultGateway = {
      address = gateway;
      interface = "eth0";
    };
    nameservers = [ gateway ];

    # sing-box 的 auto_redirect 用 nftables
    nftables = {
      enable = true;
      # 默认每次重载都会清空整个规则集，连 sing-box 自己建的表一起删掉，部署后代理就断了；
      # 关掉后 NixOS 只删除、重建它自己声明的表
      flushRuleset = false;
    };
    firewall = {
      # 只接在内网里，入站与 ImmortalWrt 时一样全放行：
      # 客户端的 DNS、被重定向进 sing-box 的连接、clash API（homelab 的 neko-master 来拉流量）都从这里进
      trustedInterfaces = [ "eth0" ];
      # 透明代理的回包从 tun 进来，严格反向路径过滤会丢掉
      checkReversePath = "loose";
    };
  };

  boot.kernelModules = [ "tcp_bbr" ];
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    # 单臂：进出是同一个网口，内核默认会给客户端发 ICMP 重定向，
    # 叫它们以后直接找主路由，流量就绕过了这台（也就绕过了代理）
    "net.ipv4.conf.all.send_redirects" = 0;
    "net.ipv4.conf.default.send_redirects" = 0;
    "net.ipv4.conf.eth0.send_redirects" = 0;
    "net.core.default_qdisc" = "fq";
    "net.ipv4.tcp_congestion_control" = "bbr";
  };

  # 不在 Nix 里声明 settings：nixpkgs 模块此时直接用 -C /etc/sing-box 读整个目录
  services.sing-box.enable = true;

  sops = {
    defaultSopsFile = secrets + "/sops/secrets/hosts/hk1box.yaml";
    secrets.sing-box-config = {
      path = "/etc/sing-box/config.json";
      owner = "sing-box";
      restartUnits = [ "sing-box.service" ];
    };
  };

  system.stateVersion = "26.05";
}
