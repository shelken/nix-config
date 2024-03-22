{lib}: rec {
  prefixLength = 24;

  hostAddress =
    lib.attrsets.mapAttrs
    (name: address: {inherit prefixLength address;})
    {
      pve155 = "192.168.6.155";
      pve156 = "192.168.6.156";
      yuuko = "192.168.6.226";
    };
}
