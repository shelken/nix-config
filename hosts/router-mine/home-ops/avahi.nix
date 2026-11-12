# home-ops 的 mDNS：avahi 在主网与 IoT 网之间反射 mDNS，让 HomeKit、Home Assistant 能发现 IoT 设备。
# 只写与默认值不同的项；nuci 只写文件，不重启服务，push 之后的重启由 just router::push 负责
{
  uci.packages = [
    "avahi-nodbus-daemon"
    "avahi-utils"
  ];

  uci.files = [
    {
      path = "/etc/avahi/avahi-daemon.conf";
      content = ''
        [server]
        check-response-ttl=no
        use-ipv4=yes
        use-ipv6=no
        allow-interfaces=br-lan.6,br-lan.50
        ratelimit-interval-usec=1000000
        ratelimit-burst=1000

        [publish]
        publish-hinfo=no
        publish-workstation=no

        [reflector]
        enable-reflector=yes
        reflect-ipv=no

        [rlimits]
        rlimit-core=0
        rlimit-data=4194304
        rlimit-fsize=0
        rlimit-nofile=768
        rlimit-stack=4194304
        rlimit-nproc=3
      '';
    }
  ];
}
