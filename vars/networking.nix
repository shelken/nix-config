{ lib }:
let
  prefixLength = 24;

  # 按类别组织主机声明
  # 每组可声明默认属性（如 user, port 等），组内条目支持 "IP" 简写或属性集覆盖
  groups = {
    # 个人主力设备 (macOS / NixOS)
    workstations = {
      user = "shelken";
      hosts = {
        yuuko = "192.168.6.11"; # yuuko 千兆有线
        sakamoto = "192.168.6.144"; # sakamoto 千兆有线
        mio = "192.168.6.248";
      };
    };

    # Homelab 虚机与集群节点
    homelab = {
      user = "shelken";
      hosts = {
        sakamoto-k8s = "192.168.6.80"; # lima-control-plane-ubuntu2404
        homelab-1 = "192.168.6.110"; # pve-qemu-worker-ubuntu2404
        yuuko-k8s = "192.168.6.81";
      };
    };

    # 基础设施 / 路由器 / 嵌入式设备
    infra = {
      user = "root";
      hosts = {
        hk1box = "192.168.6.3"; # 单臂旁路由；hosts/hk1box 的静态地址也取自这里
        pve = "192.168.6.213";
        router-home = "192.168.0.1";
        router-mine = "192.168.6.1";
        router-old = "192.168.8.1";
        # 公网 VPS 的 Tailscale 地址：业务容器把端口绑在它上面，
        # tailnet 侧的 Gatus / Prometheus 也从这里进来；sshd 不是默认端口
        vps-cc-ts = {
          address = "100.97.0.8";
          port = 60223;
        };
      };
    };
  };

  # 规范化单台主机配置：合并全局默认值、组默认值及单机显式配置
  normalizeHost =
    groupDefaults: entry:
    let
      hostConf = if builtins.isString entry then { address = entry; } else entry;
    in
    {
      inherit prefixLength;
      port = 22;
      user = "root";
    }
    // groupDefaults
    // hostConf;

  # 展平成扁平映射，供外部及 SSH 模块消费
  hostAddress = lib.pipe groups [
    (lib.mapAttrsToList (
      _: group:
      let
        groupDefaults = builtins.removeAttrs group [ "hosts" ];
      in
      lib.mapAttrs (_: entry: normalizeHost groupDefaults entry) group.hosts
    ))
    (lib.foldl' (acc: hosts: acc // hosts) { })
  ];
in
{
  inherit prefixLength hostAddress;

  ssh = {
    extraConfig = lib.concatStringsSep "\n\n" (
      lib.mapAttrsToList (
        host: conf:
        lib.concatLines (
          [
            "Host ${host}"
            "  HostName ${conf.address}"
            "  Port ${toString conf.port}"
            "  User ${conf.user}"
          ]
          ++ lib.optional (conf ? proxyJump) "  ProxyJump ${conf.proxyJump}"
        )
      ) hostAddress
    );
  };
}
