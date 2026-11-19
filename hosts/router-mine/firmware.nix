# 固件定义：发给 ASU 构建 sysupgrade 镜像的机型与发行版，由 hosts/default.nix 引用。
# 是纯数据，不是 nuci 模块。各功能用到的包仍写在功能文件的 uci.packages，构建时与这里的 packages 合并。
# 用法与锁文件见 modules/features/network/openwrt/README.md
{
  # ImmortalWrt：argon 主题与 luci-app-zerotier 只在它的源里，官方 ASU 不接受外部源
  server = "https://sysupgrade.immortalwrt.org";
  version = "25.12.2";
  target = "ramips/mt7621";
  # 机型以出厂分区为准：`strings /dev/mtd2 | grep ^model=`
  profile = "xiaomi_mi-router-cr6608";

  # 不属于任何功能的包：界面主题与中文
  packages = [
    "luci-theme-argon"
    "luci-i18n-argon-config-zh-cn"
    "luci-i18n-base-zh-cn"
  ];
}
