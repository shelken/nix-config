{ ... }:
#############################################################
#
#  yuuko-k8s：yuuko 上 Lima 里的 k3s worker，轻量弹性节点
#
#  共有配置见 ../common.nix、../lima.nix；切换与重装流程见 ../README.md
#
#############################################################
{
  imports = [
    ../common.nix
    ../lima.nix
  ];

  networking.hostName = "yuuko-k8s";

  shelken.disko.device = "/dev/vda";

  shelken.lima = {
    hostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIvvmHR3yD9rV5bStEdkjzLtr4pGdtJBOKzcq8DkRvA3 lima";
    sshPort = 60123;
    cpus = 6;
    memory = "8G";
    disk = "40G";
  };

  shelken.k3s = {
    role = "agent";
    # 轻量弹性节点：可停机、不参与 Longhorn 存储；业务亲和与部分 DaemonSet 的排除规则引用它
    nodeLabels = [ "node-type=lightweight" ];
  };
}
