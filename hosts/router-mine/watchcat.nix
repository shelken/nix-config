{
  uci.settings.watchcat = {
    watchcat = [
      {
        _type = "watchcat";
        addressfamily = "any";
        enabled = "1";
        forcedelay = "1m";
        mode = "ping_reboot";
        period = "30m";
        pinghosts = "223.5.5.5";
        pingperiod = "30s";
        pingsize = "standard";
      }
    ];
  };
}
