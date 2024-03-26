{lib}: rec {
  prefixLength = 24;

  hostAddress =
    lib.attrsets.mapAttrs
    (_name: address: {inherit prefixLength address;})
    {
      pve155 = "192.168.6.155";
      pve156 = "192.168.6.156";
      yuuko = "192.168.6.226";
      nano-zt = "192.168.168.7";
      #-- not nix
      nas-home = "192.168.0.80";
      tvbox = "192.168.6.141";
      # on pve
      pve = "192.168.6.213";
      pve-ai = "192.168.6.42";
      pve-common = "192.168.6.48";
      # router
      router-home = "192.168.0.1";
      router-mine = "192.168.6.1";
      router-old = "192.168.8.1";
    };
  mhostAddress =
    hostAddress
    // {
      nas-home = hostAddress.nas-home // {port = "233";};
    };

  ssh = {
    extraConfig =
      lib.attrsets.foldlAttrs
      (acc: host: value:
        acc
        + ''
          Host ${host}
            HostName ${value.address}
            Port ${value.port or "22"}
        '')
      ""
      mhostAddress;
  };
}
