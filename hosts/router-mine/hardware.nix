# 机型相关的值，换路由器时只改这个文件。当前机型：小米 CR6606（ramips/mt7621，一颗双频无线芯片）。
# 是纯数据，不是模块，由 network/ 下的文件 import。
# 新设备上：`wifi config` 生成射频段后读出各 radio 的 band 与 path，`ip link` 看口名，`iw dev` 看热点的 sta 设备名
{
  # 交换芯片（DSA）的 LAN 口，和 WAN 口的设备名
  lanPorts = [
    "lan1"
    "lan2"
    "lan3"
  ];
  wanDevice = "wan";

  # 射频。path 是无线芯片在系统里的硬件位置（PCIe 或 SoC 总线路径），radio 的 `+1` 后缀表示同一颗芯片的第二个频段
  radios = {
    radio0 = {
      band = "2g";
      path = "1e140000.pcie/pci0000:00/0000:00:01.0/0000:02:00.0";
      type = "mac80211";
    };
    radio1 = {
      band = "5g";
      path = "1e140000.pcie/pci0000:00/0000:00:01.0/0000:02:00.0+1";
      type = "mac80211";
    };
  };

  # 热点中继的 sta 设备名，随 5G 射频的 phy 序号而定
  hotspotDevice = "phy1-sta0";
}
