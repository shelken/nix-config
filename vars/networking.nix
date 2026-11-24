{ lib }:
let
  prefixLength = 24;

  groups = {
    workstations = {
      user = "shelken";
      hosts = {
        yuuko = "192.168.6.11";
        sakamoto = "192.168.6.144";
        mio = "192.168.6.248";
      };
    };

    homelab = {
      user = "shelken";
      hosts = {
        sakamoto-k8s = "192.168.6.80";
        homelab-1 = "192.168.6.110";
        yuuko-k8s = "192.168.6.81";
      };
    };

    infra = {
      user = "root";
      hosts = {
        hk1box = "192.168.6.3";
        pve = "192.168.6.213";
        router-home = "192.168.0.1";
        router-mine = "192.168.6.1";
        router-old = "192.168.8.1";
        vps-cc-ts = {
          address = "100.97.0.8";
          port = 60223;
        };
      };
    };
  };

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

  hk1boxWhitelist =
    let
      hosts = [
        "sakamoto-k8s"
        "yuuko-k8s"
        "homelab-1"
        "pve"
        "yuuko"
        "sakamoto"
      ];
      extraIps = [ "192.168.6.125" ];
      subnets = [ "192.168.50.0/24" ];
      ips = map (name: hostAddress.${name}.address) hosts ++ extraIps;
    in
    {
      inherit
        hosts
        extraIps
        subnets
        ips
        ;
      cidrs = map (ip: "${ip}/32") ips ++ subnets;
    };
in
{
  inherit prefixLength hostAddress hk1boxWhitelist;

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
