{
  uci.packageManager = "apk";

  imports = [
    ./system
    ./network
    ./services
    ./home-ops
    ./hk1box
  ];
}
