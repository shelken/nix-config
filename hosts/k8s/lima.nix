{
  config,
  lib,
  inputs,
  myvars,
  ...
}:
#############################################################
#
#  Lima（vz）节点共有配置：yuuko-k8s、sakamoto-k8s
#
#  引导、usernet 网卡、Lima 实例声明（system.build.limaConfig，替代 home-ops 的 lima/<宿主>.yaml）
#  limaConfig 只是数据：宿主的 lima-host 功能用自己的 pkgs 生成 lima.yaml，更新流程见 ./README.md
#
#############################################################
let
  cfg = config.shelken.lima;
  net = import (inputs.secrets + "/hosts/${config.networking.hostName}/network.nix");
in
{
  options.shelken.lima = {
    hostKey = lib.mkOption {
      type = lib.types.str;
      description = "Lima 宿主的 ~/.lima/_config/user.pub";
    };
    sshPort = lib.mkOption {
      type = lib.types.port;
      description = "Lima 为这个实例固定的宿主侧 SSH 转发端口";
    };
    cpus = lib.mkOption {
      type = lib.types.int;
      description = "虚拟机 CPU 数";
    };
    memory = lib.mkOption {
      type = lib.types.str;
      example = "8G";
      description = "虚拟机内存";
    };
    disk = lib.mkOption {
      type = lib.types.str;
      example = "40G";
      description = "系统盘大小";
    };
    additionalDisks = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "挂给实例的 Lima 附加盘名字（limactl disk create 建的）";
    };
  };

  config = {
    # vz 的磁盘与网卡都是 virtio；根分区在 virtio 盘上，initrd 必须带上驱动
    boot.initrd.availableKernelModules = [
      "virtio_pci"
      "virtio_blk"
      "virtio_scsi"
      "virtio_net"
      "xhci_pci"
    ];

    # 只用 EFI 回退路径（\EFI\BOOT\BOOTAA64.EFI），不写 NVRAM：
    # 原系统的启动项指向已被抹掉的 shim，固件找不到就会走回退路径
    boot.loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = false;
    };

    # usernet 是宿主到 guest 的管理通道，默认路由 metric 必须高于 eth1（100），流量才走桥接网卡
    systemd.network.links."10-eth0" = {
      matchConfig.PermanentMACAddress = net.usernetMac;
      linkConfig.Name = "eth0";
    };
    systemd.network.networks."20-eth0" = {
      matchConfig.Name = "eth0";
      DHCP = "ipv4";
      networkConfig = {
        DNSDefaultRoute = false;
        IPv6AcceptRA = false;
      };
      dhcpV4Config = {
        UseDNS = false;
        RouteMetric = 200;
      };
    };

    # plain 模式下 limactl start 用 Lima 自己的密钥做 SSH 就绪检查
    users.users.${myvars.username}.openssh.authorizedKeys.keys = [ cfg.hostKey ];
    # 就绪检查的脚本写死 #!/bin/bash，NixOS 没有它时 limactl start 会等到超时（做法同 nixos-lima 的 lima-init）
    systemd.tmpfiles.rules = [ "L+ /bin/bash - - - - /run/current-system/sw/bin/bash" ];

    # limactl start 最后等 /run/lima-boot-done 等于本次启动的 instance-id（每次 start 都变），
    # 原本由 cloud-init 跑的 boot 脚本写入；NixOS 不跑它们，只补这一项（做法同 nixos-lima 的 lima-init）
    fileSystems."/mnt/lima-cidata" = {
      device = "/dev/disk/by-label/cidata";
      fsType = "iso9660";
      options = [
        "ro"
        "nofail"
      ];
    };
    systemd.services.lima-boot-done = {
      wantedBy = [ "multi-user.target" ];
      unitConfig.RequiresMountsFor = "/mnt/lima-cidata";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = "sed -n 's/^LIMA_CIDATA_IID=//p' /mnt/lima-cidata/lima.env > /run/lima-boot-done";
    };

    system.build.limaConfig = {
      vmType = "vz";
      inherit (cfg) cpus memory disk;
      # guest 是 NixOS，没有 Lima guest agent，只留 SSH
      plain = true;
      ssh.localPort = cfg.sshPort;
      hostResolver.enabled = false;
      networks = [
        {
          # 非托管：socket 由宿主的 lima-host 功能常驻提供
          inherit (myvars.socketVmnet) socket;
          interface = "eth1";
          macAddress = net.lanMac;
          metric = 100;
        }
      ];
      # 只在新建实例时使用；已装好的实例不会因这里变化而重装
      images = [
        {
          location = "https://github.com/nixos-lima/nixos-lima/releases/download/v0.2.2/nixos-lima-v0.2.2-aarch64.qcow2";
          arch = "aarch64";
          digest = "sha256:dc40482a45929e4cf86ad57425e1c6ac1b376fd81111cc93ba3c9b34e7f900b6";
        }
      ];
    }
    // lib.optionalAttrs (cfg.additionalDisks != [ ]) {
      additionalDisks = map (name: {
        inherit name;
        format = false;
      }) cfg.additionalDisks;
    };
  };
}
