{
  uci.files = [
    {
      path = "/etc/hotplug.d/iface/90-odhcpd-reload";
      content = ''
        [ "$ACTION" = ifup ] || exit 0
        # 等新设备的 link-local 过完 DAD，否则 reload 后仍拿不到可用的源地址
        ( sleep 5; /etc/init.d/odhcpd reload ) &
      '';
    }
  ];
}
