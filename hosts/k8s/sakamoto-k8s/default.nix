{ myvars, ... }:
{
  imports = [
    ../common.nix
    ../lima.nix
  ];

  networking.hostName = "sakamoto-k8s";

  shelken.disko.device = "/dev/vda";

  shelken.lima = {
    hostKey = myvars.limaUserKeys.sakamoto;
    sshPort = 60122;
    cpus = 8;
    # 宿主仅 16GiB，再多会与宿主上的其他进程叠加触发 macOS 内存压缩，拖垮 etcd 延迟导致控制器集体重启
    memory = "10G";
    disk = "80G";
    additionalDisks = [ "longhorn" ];
  };

  shelken.k3s = {
    role = "server";
    # Longhorn 只在带此标签的节点建默认盘（createDefaultDiskLabeledNodes）
    nodeLabels = [ "node.longhorn.io/create-default-disk=true" ];
  };

  # Lima 附加盘 longhorn：Longhorn 的 defaultDataPath。按 UUID 挂，装机后设备名会变
  fileSystems."/mnt/lima-longhorn" = {
    device = "/dev/disk/by-uuid/02a38758-3122-4715-836a-2f1c8a32d906";
    fsType = "ext4";
    # 盘缺席时照常开机，只拦住 k3s；否则进 emergency 模式，SSH 不可用
    options = [
      "nofail"
      "x-systemd.device-timeout=30s"
    ];
  };
  # 数据盘没挂上就不启动 k3s，避免 Longhorn 把副本写到根盘（替代 Ansible 的 ExecStartPre=mountpoint）
  systemd.services.k3s.unitConfig.RequiresMountsFor = [ "/mnt/lima-longhorn" ];
}
