# 系统诊断工具：trace/监控/硬件信息
# 开发机上排障用，体积与攻击面都不小 → nixos.tui；服务器按需自己装
{ config, ... }:
{
  flake.modules.nixos.tui.imports = [ config.flake.modules.nixos.system-tools ];

  flake.modules.nixos.system-tools =
    { lib, pkgs, ... }:
    {
      # mkOrder：与迁移前一致——基础诊断工具先于桌面机的 qemu/fhs/桌面包，
      # system-path 开 ignoreCollisions，同路径冲突时排前的包胜出
      environment.systemPackages = lib.mkOrder 600 (
        with pkgs;
        [
          gnused # GNU sed, very powerful(mainly for replacing text in files)
          # system call monitoring
          strace # system call monitoring
          ltrace # library call monitoring
          bpftrace # powerful tracing tool
          tcpdump # network sniffer
          lsof # list open files

          # system monitoring
          sysstat
          iotop
          iftop
          btop
          nmon
          sysbench

          # system tools
          psmisc # killall/pstree/prtstat/fuser/...
          lm_sensors # for `sensors` command
          ethtool
          pciutils # lspci
          usbutils # lsusb
          hdparm # for disk performance, command
          dmidecode # a tool that reads information about your system's hardware from the BIOS according to the SMBIOS/DMI standard
          parted

          # 网络排障
          tealdeer # a very fast version of tldr
          just
          mtr # A network diagnostic tool
          iperf3
          socat # replacement of openbsd-netcat
          nmap # A utility for network discovery and security auditing
        ]
      );
    };
}
