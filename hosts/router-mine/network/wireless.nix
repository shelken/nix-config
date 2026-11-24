{ ... }:
let
  hw = import ../hardware.nix;
in
{
  uci.settings.wireless = {
    radio0 = {
      _type = "wifi-device";
      inherit (hw.radios.radio0) band path type;
      channel = "11";
      country = "CN";
      htmode = "HE20";
      vendor_vht = "1";
    };
    radio1 = {
      _type = "wifi-device";
      inherit (hw.radios.radio1) band path type;
      channel = "36";
      country = "CN";
      htmode = "HE80";
    };
    wifinet3 = {
      _type = "wifi-iface";
      device = "radio1";
      encryption = "psk2";
      key = "{{ sops.wifi.main.key }}";
      mode = "ap";
      network = "lan";
      ssid = "{{ sops.wifi.main.ssid }}";
    };
    wifinet8 = {
      _type = "wifi-iface";
      device = "radio1";
      encryption = "psk2";
      key = "{{ sops.wifi.noipv6.key }}";
      mode = "ap";
      network = "noipv6";
      ssid = "{{ sops.wifi.noipv6.ssid }}";
    };
    wifinet7 = {
      _type = "wifi-iface";
      device = "radio1";
      disabled = "1";
      encryption = "sae";
      key = "{{ sops.wifi.hotspot.key }}";
      mode = "sta";
      network = "hotspot hotspot_v6";
      ocv = "0";
      ssid = "{{ sops.wifi.hotspot.ssid }}";
    };
  };
}
