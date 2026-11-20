{ myvars, ... }:
{
  imports = [
    ../common.nix
    ../lima.nix
  ];

  networking.hostName = "yuuko-k8s";

  shelken.disko.device = "/dev/vda";

  shelken.lima = {
    hostKey = myvars.limaUserKeys.yuuko;
    sshPort = 60123;
    cpus = 6;
    memory = "12G";
    disk = "40G";
  };

  shelken.k3s = {
    role = "agent";
    nodeLabels = [ "node-type=lightweight" ];
  };
}
