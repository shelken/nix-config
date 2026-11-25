{
  inputs,
  myvars,
  ...
}:
let
  net = myvars.networking;
  ip = name: net.hostAddress.${name}.address;
  secretNet = host: import (inputs.secrets + "/hosts/${host}/network.nix");
  nodeMac = name: (secretNet name).lanMac;
  deviceMac = (secretNet "router-mine").dhcpMacs;
in
{
  uci.settings.dhcp = {
    dnsmasq = [
      (
        {
          _type = "dnsmasq";
          allservers = "1";
          authoritative = "1";
          cachesize = "8096";
          dns_redirect = "0";
          dnsforwardmax = "4096";
          domain = "lan";
          domainneeded = "1";
          ednspacket_max = "1232";
          expandhosts = "1";
          leasefile = "/tmp/dhcp.leases";
          local = "/lan/";
          localise_queries = "1";
          localservice = "1";
          localuse = "1";
          max_cache_ttl = "1800";
          nonegcache = "0";
          port = "53";
          readethers = "1";
          rebind_protection = "0";
          resolvfile = "/tmp/resolv.conf.d/resolv.conf.auto";
        }
        // import ../home-ops/dns.nix { bootstrapAddress = ip "sakamoto"; }
      )
    ];

    domain = [
      {
        _type = "domain";
        name = "k8s-vip.lan";
        ip = ip "sakamoto-k8s";
      }
      {
        _type = "domain";
        name = "mercury-1.lan";
        ip = "192.168.50.40";
      }
      {
        _type = "domain";
        name = "router-mine.lan";
        ip = ip "router-mine";
      }
      {
        _type = "domain";
        name = "router-home.lan";
        ip = ip "router-home";
      }
      {
        _type = "domain";
        name = "pve.lan";
        ip = ip "pve";
      }
      {
        _type = "domain";
        name = "router-f50.lan";
        ip = "192.168.10.1";
      }
      {
        _type = "domain";
        name = "sakamoto.lan";
        ip = ip "sakamoto";
      }
      {
        _type = "domain";
        name = "yuuko.lan";
        ip = ip "yuuko";
      }
    ];

    host = [
      {
        _type = "host";
        name = "pve";
        ip = ip "pve";
        leasetime = "infinite";
        mac = [ deviceMac.pve ];
        tag = "hk1box";
      }
      {
        _type = "host";
        name = "mio";
        ip = ip "mio";
        leasetime = "12h";
        mac = [
          deviceMac.mio-1
          deviceMac.mio-2
        ];
      }
      {
        _type = "host";
        name = "K2P-Mine";
        ip = "192.168.6.2";
        mac = [ deviceMac.k2p-mine ];
      }
      {
        _type = "host";
        name = "sakamoto-k8s";
        ip = ip "sakamoto-k8s";
        mac = [ (nodeMac "sakamoto-k8s") ];
        tag = "hk1box";
      }
      {
        _type = "host";
        name = "mercury-1";
        ip = "192.168.50.40";
        leasetime = "infinite";
        mac = [ deviceMac.mercury-1 ];
      }
      {
        _type = "host";
        name = "yuuko-wifi";
        ip = "192.168.6.10";
        mac = [ deviceMac.yuuko-wifi ];
      }
      {
        _type = "host";
        name = "homelab-1";
        ip = ip "homelab-1";
        mac = nodeMac "homelab-1";
        tag = "hk1box";
      }
      {
        _type = "host";
        name = "yuuko-k8s";
        ip = ip "yuuko-k8s";
        mac = [ (nodeMac "yuuko-k8s") ];
        tag = "hk1box";
      }
      {
        _type = "host";
        name = "yuuko";
        ip = ip "yuuko";
        mac = [ deviceMac.yuuko ];
        tag = "hk1box";
      }
      {
        _type = "host";
        name = "sakamoto";
        ip = ip "sakamoto";
        mac = [ deviceMac.sakamoto ];
        tag = "hk1box";
      }
      {
        _type = "host";
        name = "quest2";
        ip = "192.168.6.125";
        mac = [ deviceMac.quest2 ];
        tag = "hk1box";
      }
    ];

    lan = {
      _type = "dhcp";
      dhcpv4 = "server";
      force = "1";
      interface = "lan";
      leasetime = "12h";
      limit = "150";
      ndp = "relay";
      ra = "relay";
      ra_useleasetime = "1";
      start = "100";
    };
    noipv6 = {
      _type = "dhcp";
      dhcpv4 = "server";
      interface = "noipv6";
      leasetime = "12h";
      limit = "150";
      start = "100";
    };
    odhcpd = {
      _type = "odhcpd";
      leasefile = "/tmp/hosts/odhcpd";
      leasetrigger = "/usr/sbin/odhcpd-update";
      loglevel = "4";
    };
    wan = {
      _type = "dhcp";
      ignore = "1";
      interface = "wan";
      master = "1";
      ndp = "relay";
      ra = "relay";
      ra_useleasetime = "1";
    };
    hotspot = {
      _type = "dhcp";
      interface = "hotspot";
      ndp = "relay";
      ra = "relay";
    };
  };
}
