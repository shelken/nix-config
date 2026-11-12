# 无线：两个射频与主网、无 IPv6 网段的 SSID、热点中继。两个 IoT 的 SSID 在 home-ops/iot.nix。
# SSID 与密码在 1Password（router-mine 条目的 wifi 分组）。射频的 band、path 等机型相关的值在 hardware.nix
# 热点中继 hotspot 的开关在 LuCI 拨，声明里它是关闭的：开着热点时 just router::push 会拒绝下发，否则会把它关掉导致断网
{ ... }:
let
  hw = import ../hardware.nix;
in
{
  uci.settings.wireless = {
    radio0 = {
      _type = "wifi-device";
      inherit (hw.radios.radio0) band path type;
      cell_density = "3";
      channel = "11";
      country = "CN";
      htmode = "HE20";
      vendor_vht = "1";
    };
    radio1 = {
      _type = "wifi-device";
      inherit (hw.radios.radio1) band path type;
      cell_density = "3";
      channel = "36";
      country = "CN";
      htmode = "HE80";
    };
    wifinet3 = {
      _type = "wifi-iface";
      device = "radio1";
      encryption = "psk2";
      key = "{{ op://Personal/router-mine/wifi/main-key }}";
      mode = "ap";
      network = "lan";
      ssid = "{{ op://Personal/router-mine/wifi/main-ssid }}";
    };
    wifinet8 = {
      _type = "wifi-iface";
      device = "radio1";
      encryption = "psk2";
      key = "{{ op://Personal/router-mine/wifi/noipv6-key }}";
      mode = "ap";
      network = "noipv6";
      ssid = "{{ op://Personal/router-mine/wifi/noipv6-ssid }}";
    };
    wifinet7 = {
      _type = "wifi-iface";
      device = "radio1";
      disabled = "1";
      encryption = "sae";
      key = "{{ op://Personal/router-mine/wifi/hotspot-key }}";
      mode = "sta";
      network = "hotspot hotspot_v6";
      ocv = "0";
      ssid = "{{ op://Personal/router-mine/wifi/hotspot-ssid }}";
    };
  };
}
