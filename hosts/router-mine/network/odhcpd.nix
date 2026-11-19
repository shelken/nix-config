# odhcpd 2026.06.29 缓存 RA 的 link-local 源地址，br-lan.6 被重建（开机、push）后发送一直失败，
# 局域网设备拿不到 IPv6，直到 odhcpd reload。上游已修（openwrt/odhcpd#430），固件带上修复后删除本文件
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
