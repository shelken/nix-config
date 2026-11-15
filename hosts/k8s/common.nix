{
  config,
  lib,
  inputs,
  self,
  ...
}:
#############################################################
#
#  k3s 节点共有配置：yuuko-k8s、sakamoto-k8s、homelab-1 共用
#  主机名、磁盘设备、k3s 角色与标签是各主机自己的事，写在各自目录里
#
#  网卡 MAC 在私有 secrets 仓库的 hosts/<主机>/network.nix（求值期读取，不加密）
#  切换与重装流程见 ./README.md
#
#############################################################
let
  net = import (inputs.secrets + "/hosts/${config.networking.hostName}/network.nix");
in
{
  imports = [
    self.modules.nixos.server
    self.modules.nixos.disko
    self.modules.nixos.k3s-node
  ];

  shelken.disko.layout = "ext4";

  networking.useNetworkd = true;
  networking.useDHCP = false;
  services.resolved.enable = true;

  systemd.network = {
    # Cilium 的 devices: eth+ 与下面的 VLAN 父接口都依赖 eth1 这个名字，所以按 MAC 固定命名
    links."10-eth1" = {
      matchConfig.PermanentMACAddress = net.lanMac;
      linkConfig.Name = "eth1";
    };
    # Multus 的 macvlan 以这两个子接口为父接口；它们自己不配地址
    netdevs = lib.genAttrs [ "eth1.50" "eth1.70" ] (name: {
      netdevConfig = {
        Kind = "vlan";
        Name = name;
      };
      vlanConfig.Id = lib.toInt (lib.last (lib.splitString "." name));
    });
    networks = {
      "10-eth1" = {
        matchConfig.Name = "eth1";
        DHCP = "ipv4";
        vlan = [
          "eth1.50"
          "eth1.70"
        ];
        # home-ops ADR-0004：DNS 固定，不用 DHCP 下发的
        dns = [
          "1.1.1.1"
          "8.8.8.8"
        ];
        networkConfig = {
          DNSDefaultRoute = true;
          IPv6AcceptRA = true;
        };
        # 路由器按 MAC 做 DHCP 保留；networkd 默认发 DUID，可能拿到别的地址
        dhcpV4Config = {
          UseDNS = false;
          RouteMetric = 100;
          ClientIdentifier = "mac";
        };
        # home-ops ADR-0005：不接受 RA 的默认路由，保留 on-link IPv6
        ipv6AcceptRAConfig = {
          UseDNS = false;
          UseDomains = false;
          UseGateway = false;
        };
      };
      "30-vlan" = {
        matchConfig.Name = "eth1.*";
        networkConfig = {
          DHCP = "no";
          DNSDefaultRoute = false;
        };
        ipv6AcceptRAConfig = {
          UseDNS = false;
          UseDomains = false;
          UseGateway = false;
        };
        linkConfig.RequiredForOnline = "no";
      };
    };
  };

  system.stateVersion = "26.05";
}
