{
  # ImmortalWrt 25.12 起用 apk，固件见 firmware.nix
  uci.packageManager = "apk";

  imports = [
    ./system
    ./network
    ./services
    ./home-ops
    ./hk1box
  ];
}
