{
  self,
  config,
  lib,
  modulesPath,
  secrets,
  ...
}:
#############################################################
#
#  VPS 共有配置：真机 vps-cc 与它的演练机 vps-test 共用
#  网络、主机名、硬件报告是各主机自己的事，写在各自目录里
#
#  磁盘：BIOS + GPT + ext4，见 modules/features/nixos/disko.nix
#  登录：root 与 shelken 仅密钥登录；口令哈希由 sops 在开机时解出（modules/features/nixos/sops.nix）
#  容器：docker compose 由 home-ops 部署，这里只提供 docker 守护进程
#
#############################################################
{
  imports = [
    self.modules.nixos.server
    self.modules.nixos.disko
    self.modules.nixos.sops
    self.modules.nixos.docker
    # KVM 虚拟机的 virtio 驱动（x86_64 内核里它们是模块，必须进 initrd）
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  shelken.disko = {
    device = "/dev/vda";
    layout = "ext4";
    boot = "bios";
  };

  # 沿用旧系统的 eth0 命名，网络参数里写的就是 eth0
  networking.usePredictableInterfaceNames = false;

  # BBR 等网络调优；服务商路径 MTU 低于 1500（接口 MTU 见各主机），tcp_mtu_probing 兜底路径 MTU 黑洞
  boot.kernelModules = [ "tcp_bbr" ];
  boot.kernel.sysctl = {
    "net.ipv4.tcp_congestion_control" = "bbr";
    "net.ipv4.tcp_fastopen" = 3;
    # 路径 MTU 黑洞时自动探测
    "net.ipv4.tcp_mtu_probing" = 1;
    "net.core.rmem_max" = 67108864;
    "net.core.wmem_max" = 67108864;
    "net.ipv4.tcp_rmem" = "4096 87380 33554432";
    "net.ipv4.tcp_wmem" = "4096 65536 33554432";
    # caddy、fluent-bit 等会监听大量文件
    "fs.inotify.max_user_instances" = 8192;
    "fs.inotify.max_user_watches" = 1048576;
  };

  # 服务器在美国：国内 NTP 太远，覆盖 core 的默认值（列表选项会合并，所以要 mkForce）
  networking.timeServers = lib.mkForce [
    "time.cloudflare.com"
    "ntp.ubuntu.com"
  ];
  networking.nameservers = [
    "127.0.0.1" # docker 里的 dnsmasq，转到 mosdns；容器没起来时直接拒绝连接，立刻落到下一个
    "8.8.8.8"
  ];
  # openresolv 默认只把本机（127.0.0.1）解析器写进 resolv.conf，丢掉后面的 8.8.8.8；
  # 而 127.0.0.1 要等 docker 里的 dnsmasq 起来才有人应答，起来之前（包括首次拉镜像）整机解析不了域名
  networking.resolvconf.extraConfig = "resolv_conf_local_only=NO";

  services.openssh.ports = [ 60223 ];

  # 防火墙只管宿主进程与 network_mode: host 的容器（derp、hysteria2、anytls）；
  # docker 用 ports 发布的端口走 NAT/FORWARD，绕过这里，是否对外取决于 compose 里有没有映射。
  # 443 是 caddy 的发布端口，列在这里只是声明
  networking.firewall = {
    allowedTCPPorts = [
      443
      8666 # derp
      5444 # anytls
    ];
    allowedUDPPorts = [
      443
      3478 # derp stun
      10357 # hysteria2
    ];
    trustedInterfaces = [ "tailscale0" ];
    # tailscale 接受子网路由，严格反向路径过滤会丢掉非对称流量
    checkReversePath = "loose";
  };

  services.tailscale = {
    enable = true;
    useRoutingFeatures = "client";
    # 放行 41641/udp，让对端能直连这台有公网地址的机器，不必先靠打洞
    openFirewall = true;
    extraSetFlags = [
      "--accept-routes"
      "--accept-dns=false"
    ];
  };

  # 多个容器把端口绑在 tailscale 地址上，守护进程要等 tailscaled
  systemd.services.docker = {
    after = [ "tailscaled.service" ];
    wants = [ "tailscaled.service" ];
  };
  # 国外服务器连不上国内镜像源
  virtualisation.docker.daemon.settings.registry-mirrors = lib.mkForce [ ];
  # 业务数据目录，由 home-ops 的 compose 部署写入
  systemd.tmpfiles.rules = [ "d /data/docker 0755 root root -" ];

  sops = {
    defaultSopsFile = secrets + "/sops/secrets/hosts/vps-cc.yaml";
    secrets = {
      shelken-password-hash.neededForUsers = true;
      root-password-hash.neededForUsers = true;
    };
  };
  users.users = {
    shelken = {
      initialHashedPassword = lib.mkForce null;
      hashedPasswordFile = config.sops.secrets.shelken-password-hash.path;
    };
    root = {
      initialHashedPassword = lib.mkForce null;
      hashedPasswordFile = config.sops.secrets.root-password-hash.path;
    };
  };

  system.stateVersion = "26.05";
}
