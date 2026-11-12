# DNS 与 DHCP。IP 优先取自 vars/networking.nix；静态租约的 MAC 在 1Password（router-mine 条目的 dhcp 分组）。
# lan、viot 的网关与 DNS 选项（指向 hk1box）在 hk1box/dhcp.nix
{ lib, ... }:
let
  net = import ../../../vars/networking.nix { inherit lib; };
  ip = name: net.hostAddress.${name}.address;
  mac = name: "{{ op://Personal/router-mine/dhcp/${name} }}";
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
          # IoT 的 DNS 发到 hk1box，不能被劫持回路由器（passwall 开机会把它改回 1）
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
          min_ttl = "3600";
          nonegcache = "1";
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
        mac = [ (mac "pve") ];
      }
      {
        _type = "host";
        name = "mio";
        ip = ip "mio";
        leasetime = "12h";
        mac = [
          (mac "mio-1")
          (mac "mio-2")
        ];
      }
      {
        _type = "host";
        name = "K2P-Mine";
        ip = "192.168.6.2";
        mac = [ (mac "k2p-mine") ];
      }
      {
        _type = "host";
        name = "sakamoto-k8s";
        ip = ip "sakamoto-k8s";
        mac = [ (mac "sakamoto-k8s") ];
      }
      {
        _type = "host";
        name = "mercury-1";
        ip = "192.168.50.40";
        leasetime = "infinite";
        mac = [ (mac "mercury-1") ];
      }
      {
        _type = "host";
        name = "yuuko-wifi";
        ip = "192.168.6.10";
        mac = [ (mac "yuuko-wifi") ];
      }
      {
        _type = "host";
        name = "homelab-1";
        ip = ip "homelab-1";
        mac = mac "homelab-1";
      }
      {
        _type = "host";
        name = "yuuko-k8s";
        ip = ip "yuuko-k8s";
        mac = [ (mac "yuuko-k8s") ];
      }
      {
        _type = "host";
        name = "yuuko";
        ip = ip "yuuko";
        mac = [ (mac "yuuko") ];
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
      ra_dns = "0";
      ra_management = "1";
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
    viot = {
      _type = "dhcp";
      interface = "viot";
      leasetime = "12h";
      limit = "150";
      start = "100";
    };
    vipv6 = {
      _type = "dhcp";
      dhcpv4 = "server";
      interface = "vipv6";
      leasetime = "12h";
      limit = "150";
      start = "100";
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
    wwan2 = {
      _type = "dhcp";
      interface = "wwan2";
      ndp = "relay";
      ra = "relay";
    };
  };
}
