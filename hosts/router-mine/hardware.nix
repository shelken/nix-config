{
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
