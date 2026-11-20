{ config, ... }:
{
  flake.modules.nixos.tui.imports = [ config.flake.modules.nixos.diagnostics ];

  flake.modules.nixos.diagnostics =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        gnused
        strace
        ltrace
        bpftrace
        tcpdump
        lsof

        sysstat
        iotop
        iftop
        btop
        nmon
        sysbench

        psmisc
        lm_sensors
        ethtool
        pciutils
        usbutils
        hdparm
        dmidecode
        parted

        tealdeer
        just
        mtr
        iperf3
        socat
        nmap
      ];
    };
}
