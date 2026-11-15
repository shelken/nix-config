# k3s-node：家里 k3s 集群的节点（控制面或 worker）的系统层配置，只在 NixOS 上用
# 可选功能：节点主机经 hosts/k8s/common.nix 导入，并设置 shelken.k3s.*
# k3s 配置以 home-ops 原 Ansible 渲染出的 /etc/rancher/k3s/config.yaml 为准，逐项复现
{ ... }:
{
  flake.modules.nixos.k3s-node =
    {
      config,
      lib,
      pkgs,
      myvars,
      ...
    }:
    let
      cfg = config.shelken.k3s;
      isServer = cfg.role == "server";
      yaml = pkgs.formats.yaml { };

      kubeletArgs = [
        "image-gc-low-threshold=50"
        "image-gc-high-threshold=55"
        "feature-gates=ImageVolume=true"
        "allowed-unsafe-sysctls=net.ipv6.*"
      ]
      # 只在控制面预留内存：Pod 吃满内存会挤掉 etcd 的页缓存，导致 k3s 退出
      ++ lib.optional isServer "system-reserved=memory=4500Mi"
      # 磁盘两项是在覆盖默认值，必须连同内存一起重复写
      ++ [ "eviction-hard=memory.available<500Mi,nodefs.available<5%,imagefs.available<5%" ];

      controllerArgs = [
        "bind-address=0.0.0.0"
        "feature-gates=ImageVolume=true"
        "leader-elect-lease-duration=60s"
        "leader-elect-renew-deadline=40s"
        "leader-elect-retry-period=10s"
      ];

      commonConfig = {
        kubelet-arg = kubeletArgs;
        node-ip = cfg.nodeIP;
        node-label = cfg.nodeLabels;
        private-registry = "${./registries.yaml}";
      };

      serverConfig = {
        cluster-init = true;
        cluster-cidr = "10.42.0.0/16";
        disable = [
          "flannel"
          "local-storage"
          "servicelb"
          "traefik"
          "coredns"
          "metrics-server"
        ];
        disable-cloud-controller = true;
        disable-kube-proxy = true;
        disable-network-policy = true;
        docker = false;
        embedded-registry = false;
        etcd-arg = [
          "election-timeout=5000"
          "heartbeat-interval=500"
          # 必须是纳秒整数：k3s 经 yaml 写 etcd 配置，写成 1s 会反序列化失败
          "warning-apply-duration=1000000000"
          "warning-unary-request-duration=1000000000"
        ];
        etcd-disable-snapshots = true;
        etcd-expose-metrics = true;
        flannel-backend = "none";
        kube-apiserver-arg = [
          "--feature-gates=ImageVolume=true,MutatingAdmissionPolicy=true,ResourceHealthStatus=true"
          "--runtime-config=admissionregistration.k8s.io/v1beta1=true"
          "--audit-policy-file=${./audit-policy.yaml}"
          "--audit-log-path=/var/lib/rancher/k3s/server/logs/audit.log"
          "--audit-log-maxage=14"
          "--audit-log-maxbackup=20"
          "--audit-log-maxsize=50"
        ];
        kube-controller-manager-arg = controllerArgs;
        kube-scheduler-arg = controllerArgs;
        # 控制面恢复的 etcd 里 Secret 已加密，缺了这项就读不出来
        secrets-encryption = true;
        service-cidr = "10.43.0.0/16";
        tls-san = [
          cfg.nodeIP
          "k8s-vip.lan"
          "k8s-vip"
          "k8s-vip.ooooo.space"
        ];
        write-kubeconfig-mode = "0600";
      };
    in
    {
      options.shelken.k3s = {
        role = lib.mkOption {
          type = lib.types.enum [
            "server"
            "agent"
          ];
          description = "控制面（server）或 worker（agent）";
        };
        nodeLabels = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "节点注册时带上的标签";
        };
        nodeIP = lib.mkOption {
          type = lib.types.str;
          default = myvars.networking.hostAddress.${config.networking.hostName}.address;
          description = "节点通告的地址，默认取 vars/networking.nix 里同名主机的地址";
        };
      };

      config = lib.mkMerge [
        {
          services.k3s = {
            enable = true;
            # 写死 minor：升级 minor 必须有意为之，先 server 后 agent
            package = pkgs.k3s_1_37;
            inherit (cfg) role;
            configPath = yaml.generate "k3s-config.yaml" (
              commonConfig // lib.optionalAttrs isServer serverConfig
            );
          };

          # Longhorn：需要 iscsid、NFS 与加密卷工具
          services.openiscsi = {
            enable = true;
            name = "iqn.2026-11.lan.home:${config.networking.hostName}";
          };
          boot.supportedFilesystems.nfs = true;
          environment.systemPackages = with pkgs; [
            nfs-utils
            cryptsetup
            e2fsprogs
            openiscsi
          ];
          # Longhorn 的容器 nsenter 进宿主后沿用容器自己的 PATH，找不到 NixOS 的命令
          systemd.tmpfiles.rules = [ "L+ /usr/local/bin - - - - /run/current-system/sw/bin" ];
          systemd.services.k3s = {
            after = [ "iscsid.service" ];
            wants = [ "iscsid.service" ];
          };

          boot.kernelModules = [
            "tcp_bbr" # sysctl 里的拥塞控制算法
            "iscsi_tcp" # Longhorn 经 iSCSI 挂卷
            "dm_crypt" # Longhorn 加密卷
            "cifs" # 挂载 SMB 卷
            "nls_utf8" # cifs 的 iocharset=utf8 依赖
          ];
          boot.kernel.sysctl = {
            "fs.inotify.max_user_instances" = 8192;
            "fs.inotify.max_user_watches" = 1048576;
            "net.core.rmem_max" = 67108864;
            "net.core.wmem_max" = 67108864;
            # 邻居表（ARP/NDP）调大，避免大量 Pod 网卡把表挤满
            "net.ipv4.neigh.default.gc_thresh1" = 4096;
            "net.ipv4.neigh.default.gc_thresh2" = 8192;
            "net.ipv4.neigh.default.gc_thresh3" = 16384;
            "net.ipv4.tcp_congestion_control" = "bbr";
            "net.ipv4.tcp_fastopen" = 3;
            # 路径 MTU 黑洞时自动探测
            "net.ipv4.tcp_mtu_probing" = 1;
            "net.ipv4.tcp_rmem" = "4096 87380 33554432";
            "net.ipv4.tcp_wmem" = "4096 65536 33554432";
            "net.ipv4.tcp_window_scaling" = 1;
            "user.max_user_namespaces" = 55334;
          };

          # kubelet 在有 swap 时默认拒绝启动，覆盖 server 角色的 zram
          zramSwap.enable = lib.mkForce false;

          # Cilium、BGP 179、kubelet、etcd、Longhorn 的端口由集群管理，生产的 Ubuntu 也没有主机防火墙
          networking.firewall.enable = false;

          # Lima 节点随宿主 macOS 睡眠暂停，恢复后时钟会瞬间偏差很大，必须允许任意次步进校时
          services.chrony = {
            enable = true;
            extraConfig = "makestep 1 -1";
          };
        }

        (lib.mkIf (!isServer) {
          services.k3s = {
            serverAddr = "https://${myvars.networking.hostAddress."sakamoto-k8s".address}:6443";
          };
        })
      ];
    };
}
