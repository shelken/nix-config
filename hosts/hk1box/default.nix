{
  self,
  myvars,
  inputs,
  ...
}:
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
    usePredictableInterfaceNames = false;
    useDHCP = false;
    # 这台 efuse 为空，u-boot 只按 SoC 派生一个稳定但不同的 MAC；钉回 ImmortalWrt 时的值
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
      # 开启 flushRuleset 会在重载时清空整个规则集，连 sing-box（auto_redirect）自己建的表一起删掉，导致代理中断；
      # 关掉后 NixOS 只删除、重建它自己声明的表
      flushRuleset = false;
    };
    firewall = {
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

  sops.defaultSopsFile = inputs.secrets + "/sops/secrets/hosts/hk1box.yaml";

  system.stateVersion = "26.05";
}
