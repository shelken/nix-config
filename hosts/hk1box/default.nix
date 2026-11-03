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
#  硬件与引导见 ./hardware.nix，eMMC 分区见 ./disk.nix，试机镜像见 ./image.nix，
#  sing-box 与订阅拉取见 ./sing-box.nix；从 ImmortalWrt 切过来的步骤见 ./README.md
#
#  单臂：只有一个网口，客户端把网关指向这台；它把流量交给 sing-box，再从同一个网口发给主路由。
#  哪些设备走代理由 sing-box 配置（订阅 overlay 里的白名单）决定，名单外的由内核直接转发
#  地址：沿用 vars/networking.nix 里的登记（同一网段，网关是主路由）。
#  本机自己的 DNS 必须指向主路由：sing-box 的 dns-local-system 走系统解析，指回本机会绕成环
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
    self.modules.nixos.nix-icache-system
    ./hardware.nix
    ./disk.nix
    ./image.nix
    ./sing-box.nix
  ];

  networking = {
    hostName = "hk1box";
    # 只有一个网口，沿用 ImmortalWrt 时的 eth0
    usePredictableInterfaceNames = false;
    useDHCP = false;
    # 这台 efuse 为空，u-boot 只按 SoC 派生一个稳定但不同的 MAC；钉回 ImmortalWrt 时的值
    # （生成 systemd `.link`，由 udevd 应用，不依赖 networkd）
    interfaces.eth0.macAddress = "00:e5:00:00:15:eb";
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
      # 客户端的 DNS（router 底模的 dns-in，53）、被重定向进 sing-box 的连接、
      # clash API（9090，homelab 的 neko-master 来拉流量，靠 overlay 里的 secret 保护）都从这里进
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

  # 本机的系统密钥（目前只有 sing-box 的订阅 URL），只有管理员与这台的 age 密钥能解
  sops.defaultSopsFile = secrets + "/sops/secrets/hosts/hk1box.yaml";

  system.stateVersion = "26.05";
}
