{
  self,
  config,
  lib,
  modulesPath,
  inputs,
  ...
}:
{
  imports = [
    self.modules.nixos.server
    self.modules.nixos.disko
    self.modules.nixos.sops
    self.modules.nixos.docker
    # 开机时内核要先认出系统盘才能挂根分区，而 virtio 磁盘与网卡驱动在内核里是模块，必须列进 initrd；
    # 没有硬件报告（nixos-facter）时，靠它声明这些驱动，缺了就会开机找不到根分区
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  shelken.disko = {
    device = "/dev/vda";
    layout = "ext4";
    boot = "bios";
  };

  networking.usePredictableInterfaceNames = false;

  # BBR 等网络调优；服务商路径 MTU 低于 1500（接口 MTU 见各主机），tcp_mtu_probing 兜底路径 MTU 黑洞
  boot.kernelModules = [ "tcp_bbr" ];
  boot.kernel.sysctl = {
    "net.ipv4.tcp_congestion_control" = "bbr";
    "net.ipv4.tcp_fastopen" = 3;
    "net.ipv4.tcp_mtu_probing" = 1;
    "net.core.rmem_max" = 67108864;
    "net.core.wmem_max" = 67108864;
    "net.ipv4.tcp_rmem" = "4096 87380 33554432";
    "net.ipv4.tcp_wmem" = "4096 65536 33554432";
    "fs.inotify.max_user_instances" = 8192;
    "fs.inotify.max_user_watches" = 1048576;
  };

  networking.timeServers = lib.mkForce [
    "time.cloudflare.com"
    "ntp.ubuntu.com"
  ];
  networking.nameservers = [
    "127.0.0.1"
    "8.8.8.8"
  ];
  # openresolv 默认只把本机（127.0.0.1）解析器写进 resolv.conf，丢掉后面的 8.8.8.8；
  # 而 127.0.0.1 要等 docker 里的 dnsmasq 起来才有人应答，起来之前（包括首次拉镜像）整机解析不了域名
  networking.resolvconf.extraConfig = "resolv_conf_local_only=NO";

  services.openssh.ports = [ 60223 ];

  # 防火墙只管宿主进程与 network_mode: host 的容器（derp、hysteria2、anytls）；
  # docker 用 ports 发布的端口走 NAT/FORWARD，绕过这里，是否对外取决于 compose 里有没有映射。
  networking.firewall = {
    allowedTCPPorts = [
      443
      8666
      5444
    ];
    allowedUDPPorts = [
      443
      3478
      10357
    ];
    trustedInterfaces = [ "tailscale0" ];
    # tailscale 接受子网路由，严格反向路径过滤会丢掉非对称流量
    checkReversePath = "loose";
  };

  services.tailscale = {
    enable = true;
    useRoutingFeatures = "client";
    openFirewall = true;
    extraSetFlags = [
      "--accept-routes"
      "--accept-dns=false"
    ];
  };

  systemd.services.docker = {
    after = [ "tailscaled.service" ];
    wants = [ "tailscaled.service" ];
  };
  virtualisation.docker.daemon.settings.registry-mirrors = lib.mkForce [ ];
  systemd.tmpfiles.rules = [ "d /data/docker 0755 root root -" ];

  sops = {
    defaultSopsFile = inputs.secrets + "/sops/secrets/hosts/vps-cc.yaml";
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
