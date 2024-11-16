{lib}: let
  DEFAULT_PORT = "22";
  DEFAULT_USER = "root";
  shelken-user = {
    user = "shelken";
  };
  prefixLength = 24;
  combine-net = lib.attrsets.mapAttrs (_name: address: {inherit prefixLength address;});
  combine-user = origin-set: user-set: (lib.attrsets.mapAttrs (_name: value: value // user-set) origin-set);
  nix-host =
    combine-user
    (combine-net
      {
        pve155 = "192.168.6.155";
        pve156 = "192.168.6.156";
        yuuko = "192.168.6.245";
        sakamoto = "192.168.6.144";
        mio = "192.168.6.244";
        nano-zt = "192.168.168.7";
      })
    shelken-user;
  other-host =
    combine-net
    {
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
in rec {
  inherit prefixLength;
  hostAddress = nix-host // other-host;
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
            Port ${value.port or DEFAULT_PORT}
            User ${value.user or DEFAULT_USER}
        '')
      ""
      mhostAddress;
  };
}
