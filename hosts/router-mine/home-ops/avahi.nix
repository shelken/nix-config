{
  # avahi-utils 依赖 dbus 版 avahi，与 nodbus 版互斥，固件构建会失败
  uci.packages = [ "avahi-nodbus-daemon" ];

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
